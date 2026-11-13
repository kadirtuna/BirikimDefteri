#!/usr/bin/env bash
# launchd saatte bir çalıştırır; Mac uykudaysa uyanınca çalışır.
# 1. Uygulamanın iPhone'da yazdığı JSON yedeklerini iCloud Drive > Birikim Defteri Yedekleri'ne çeker.
# 2. İmzanın bitmesine 72 saatten az kaldıysa uygulamayı iPhone'a yeniden yükler (başlatmaz).
#    iPhone uykudayken Wi-Fi'den yanıt vermeyebilir; saatlik deneme bu yüzden.
# 3. Xcode'daki Apple hesabı çıkış yapmışsa imza dolmadan önce uyarır.
# Bildirimler sebebe göre değişir ve aynı uyarı birkaç saatte bir tekrarlanır.
# iPhone kabloyla bağlı ya da Mac ile aynı ağda olmalı.
#
#   ./scripts/auto-install.sh             Şimdi kontrol et, gerekirse yükle
#   ./scripts/auto-install.sh --force     Süreye bakmadan yeniden yükle
#   ./scripts/auto-install.sh --enable    Zamanlanmış görevi kur
#   ./scripts/auto-install.sh --disable   Zamanlanmış görevi kaldır
#
# Kayıt: ~/Library/Logs/BirikimDefteri/auto-install.log
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
source scripts/lib.sh
LABEL="com.kadirtuna.birikimdefteri.autoinstall"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/BirikimDefteri"
LOG="$LOG_DIR/auto-install.log"
STATE="build/installed-profile-expiry"
RENEW_BEFORE_HOURS=72
NOTIFY_STATE="build/notified"
BUNDLE_ID="com.kadirtuna.birikimdefteri"
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
if [[ -d "$ICLOUD" ]]; then
    BACKUP_DIR="$ICLOUD/Birikim Defteri Yedekleri"
else
    BACKUP_DIR="$HOME/Documents/Birikim Defteri Yedekleri"
fi
KEEP_BACKUPS=90
STALE_BACKUP_DAYS=7

notify() {
    osascript -e "display notification \"$1\" with title \"Birikim Defteri\"" >/dev/null 2>&1 || true
}

# Aynı türdeki uyarıyı `hours` saatte en çok bir kez gösterir (görev saatlik çalışıyor).
notify_every() {
    local key="$1" hours="$2" message="$3" last_time=0
    mkdir -p "$NOTIFY_STATE"
    [[ -f "$NOTIFY_STATE/$key" ]] && last_time="$(cat "$NOTIFY_STATE/$key")"
    (( $(date +%s) - ${last_time:-0} < hours * 3600 )) && return
    date +%s >"$NOTIFY_STATE/$key"
    notify "$message"
}

to_epoch() { date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null; }
to_local() { date -j -f "%s" "$1" "+%d.%m.%Y %H:%M"; }

case "${1:-}" in
--enable)
    mkdir -p "$(dirname "$AGENT")" "$LOG_DIR"
    cat >"$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$ROOT/scripts/auto-install.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    if launchctl bootstrap "gui/$(id -u)" "$AGENT"; then
        echo "Zamanlanmış görev kuruldu: saatte bir. Kayıt: $LOG"
        exit 0
    fi
    echo "Zamanlanmış görev kurulamadı." >&2
    exit 1
    ;;
--disable)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$AGENT"
    echo "Zamanlanmış görev kaldırıldı."
    exit 0
    ;;
--force | "")
    ;;
*)
    echo "Kullanım: $0 [--force | --enable | --disable]" >&2
    exit 2
    ;;
esac

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date '+%d.%m.%Y %H:%M:%S') kontrol"

# Telefondaki yedeklerden Mac'te olmayanları kopyalar, en eski fazlalıkları siler.
pull_backups() {
    local udid listing names copied=0
    udid="$(cat build/device-udid 2>/dev/null)"
    [[ -n "$udid" ]] || { echo "Yedek: cihaz henüz bilinmiyor (önce install.sh çalışmalı)."; return 1; }
    mkdir -p "$BACKUP_DIR" || { echo "Yedek: klasör oluşturulamadı: $BACKUP_DIR"; return 1; }
    xcrun devicectl --timeout 25 device info lockState --device "$udid" >/dev/null 2>&1 \
        || { echo "Yedek: iPhone'a ulaşılamadı, bu sefer yedek alınmadı."; return 1; }
    listing="$(mktemp)"
    xcrun devicectl device info files --device "$udid" --domain-type appDataContainer \
        --domain-identifier "$BUNDLE_ID" --subdirectory "Documents/Yedekler" --json-output "$listing" >/dev/null 2>&1
    names="$(/usr/bin/python3 -I -c '
import json, sys
try:
    files = json.load(open(sys.argv[1]))["result"]["files"]
except Exception:
    files = []
for f in files:
    name = f.get("name", "")
    if name.startswith("BirikimDefteri-") and name.endswith(".json"):
        print(name)
' "$listing")"
    rm -f "$listing"
    while IFS= read -r name; do
        [[ -n "$name" && ! -f "$BACKUP_DIR/$name" ]] || continue
        if xcrun devicectl device copy from --device "$udid" --domain-type appDataContainer \
            --domain-identifier "$BUNDLE_ID" --source "Documents/Yedekler/$name" --destination "$BACKUP_DIR/$name" >/dev/null 2>&1; then
            copied=$((copied + 1))
        fi
    done <<<"$names"
    ls -1 "$BACKUP_DIR" 2>/dev/null | grep -E '^BirikimDefteri-.*\.json$' | sort -r | tail -n +$((KEEP_BACKUPS + 1)) \
        | while IFS= read -r old; do rm -f "$BACKUP_DIR/$old"; done
    echo "Yedek: $copied yeni dosya → $BACKUP_DIR"
}

pull_backups || true
newest="$(ls -1t "$BACKUP_DIR"/BirikimDefteri-*.json 2>/dev/null | head -1)"
if [[ -n "$newest" ]] && (( ($(date +%s) - $(stat -f %m "$newest")) / 86400 >= STALE_BACKUP_DAYS )); then
    notify_every backup 24 "Son yedek $STALE_BACKUP_DAYS günden eski. iPhone'u Mac ile aynı Wi-Fi'de açık bırakın."
fi

expiry_epoch="$(to_epoch "$(cat "$STATE" 2>/dev/null)")"
hours_left=""
[[ -n "$expiry_epoch" ]] && hours_left=$(( (expiry_epoch - $(date +%s)) / 3600 ))
if [[ -n "$hours_left" ]] && (( hours_left < 0 )); then
    expiry_note="İmzanın süresi $(to_local "$expiry_epoch") tarihinde doldu; uygulama şu an açılmıyor."
elif [[ -n "$hours_left" ]]; then
    expiry_note="İmza $(to_local "$expiry_epoch") tarihinde doluyor."
else
    expiry_note=""
fi

# Hesap çıkış yapmışsa yenileme zamanı gelmeden uyar; düzeltmek için günler kalsın.
account_state=0
xcode_account_state || account_state=$?
if (( account_state == 1 )); then
    echo "Xcode'da Apple hesabı yok. $expiry_note"
    notify_every account 12 "Xcode'da Apple hesabınız çıkış yapmış; imza yenilenemez. $expiry_note Xcode > Ayarlar > Apple Accounts'tan giriş yapın."
fi

if [[ "${1:-}" != "--force" && -n "$hours_left" ]] && (( hours_left > RENEW_BEFORE_HOURS )); then
    echo "İmza $(to_local "$expiry_epoch") tarihine kadar geçerli ($hours_left saat kaldı); yenileme gerekmiyor."
    echo "=== bitti (0)"
    exit 0
fi

SKIP_LAUNCH=1 ./scripts/install.sh
status=$?
if (( status == 0 )); then
    rm -f "$NOTIFY_STATE/account" "$NOTIFY_STATE/unreachable" "$NOTIFY_STATE/build"
    new_epoch="$(to_epoch "$(cat "$STATE" 2>/dev/null)")"
    notify "İmza yenilendi. Yeni geçerlilik: $(to_local "${new_epoch:-$(date +%s)}")"
    echo "=== bitti (0)"
    exit 0
fi

case "$status" in
"$EXIT_NO_ACCOUNT")
    # Yukarıda zaten uyarıldı.
    ;;
"$EXIT_UNREACHABLE")
    # Telefon uykudayken sık olur; yalnızca süre azaldıysa ve 6 saatte bir uyar.
    if [[ -z "$hours_left" ]] || (( hours_left < 24 )); then
        notify_every unreachable 6 "İmza yenilenemedi: iPhone'a ulaşılamadı. $expiry_note iPhone'un kilidini açıp Mac ile aynı Wi-Fi'de bırakın ya da kabloyla bağlayın."
    fi
    ;;
*)
    notify_every build 6 "İmza yenilenemedi: derleme hatası. $expiry_note Ayrıntılar: $LOG"
    ;;
esac
echo "=== bitti ($status)"
exit "$status"
