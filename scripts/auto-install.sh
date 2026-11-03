#!/usr/bin/env bash
# launchd her gün 09:00 ve 20:30'da çalıştırır; Mac o saatte uykudaysa uyanınca çalışır.
# 1. Uygulamanın iPhone'da yazdığı JSON yedeklerini iCloud Drive > Birikim Defteri Yedekleri'ne çeker.
# 2. İmzanın bitmesine 48 saatten az kaldıysa uygulamayı iPhone'a yeniden yükler (başlatmaz).
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
LABEL="com.kadirtuna.birikimdefteri.autoinstall"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/BirikimDefteri"
LOG="$LOG_DIR/auto-install.log"
STATE="build/installed-profile-expiry"
RENEW_BEFORE_HOURS=48
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
    <key>StartCalendarInterval</key>
    <array>
        <dict>
            <key>Hour</key>
            <integer>9</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>20</integer>
            <key>Minute</key>
            <integer>30</integer>
        </dict>
    </array>
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
        echo "Zamanlanmış görev kuruldu: her gün 09:00 ve 20:30. Kayıt: $LOG"
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
    notify "Son yedek $STALE_BACKUP_DAYS günden eski. iPhone'u Mac ile aynı Wi-Fi'de açık bırakın."
fi

if [[ "${1:-}" != "--force" && -f "$STATE" ]]; then
    expiry_epoch="$(to_epoch "$(cat "$STATE")")"
    if [[ -n "$expiry_epoch" ]]; then
        hours_left=$(( (expiry_epoch - $(date +%s)) / 3600 ))
        if (( hours_left > RENEW_BEFORE_HOURS )); then
            echo "İmza $(to_local "$expiry_epoch") tarihine kadar geçerli ($hours_left saat kaldı); yenileme gerekmiyor."
            echo "=== bitti (0)"
            exit 0
        fi
    fi
fi

if SKIP_LAUNCH=1 ./scripts/install.sh; then
    new_epoch="$(to_epoch "$(cat "$STATE" 2>/dev/null)")"
    notify "İmza yenilendi. Yeni geçerlilik: $(to_local "${new_epoch:-$(date +%s)}")"
    echo "=== bitti (0)"
else
    notify "İmza yenilenemedi. iPhone açık ve Mac ile aynı Wi-Fi'de mi? Bir sonraki kontrolde yeniden denenecek."
    echo "=== bitti (1)"
    exit 1
fi
