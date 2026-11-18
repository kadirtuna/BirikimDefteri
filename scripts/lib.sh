# install.sh ile auto-install.sh'nin ortak yardımcıları. Doğrudan çalıştırılmaz, `source` edilir.

# install.sh'nin çıkış kodları; otomatik yenileme bunlara göre doğru bildirimi gösterir.
EXIT_NO_ACCOUNT=3
EXIT_UNREACHABLE=4
# ONLY_WHEN_LOCKED=1 iken telefon kullanımdaydı (kilidi açık); açık uygulamayı kapatmamak için yüklenmedi.
EXIT_IN_USE=5
# İmza anahtarına o an erişilemedi (errSecInternalComponent); geçici.
EXIT_MAC_BUSY=6

# iPhone kilitli mi? 0: kilitli, 1: kilidi açık, 2: ulaşılamadı.
device_lock_state() {
    local json; json="$(mktemp)"
    if ! xcrun devicectl --timeout 30 device info lockState --device "$1" --json-output "$json" >/dev/null 2>&1; then
        rm -f "$json"; return 2
    fi
    local state=0
    /usr/bin/python3 -I -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1]))["result"].get("passcodeRequired") else 1)' "$json" || state=$?
    rm -f "$json"
    return "$state"
}

# Xcode'da Apple hesabı var mı? 0: var, 1: yok, 2: bilinmiyor (Xcode ayar biçimi tanınmadı).
# Ücretsiz hesapta 7 günlük imzayı Apple yalnızca Xcode'da oturum açıkken verir.
xcode_account_state() {
    defaults export com.apple.dt.Xcode - 2>/dev/null | /usr/bin/python3 -I -c '
import plistlib, sys
try:
    lists = plistlib.loads(sys.stdin.buffer.read()).get("DVTDeveloperAccountManagerAppleIDLists")
except Exception:
    sys.exit(2)
if not isinstance(lists, dict):
    sys.exit(2)
sys.exit(0 if any(isinstance(value, list) and value for value in lists.values()) else 1)
'
}

NO_ACCOUNT_HELP="Xcode'da oturum açık bir Apple hesabı yok; Apple yeni 7 günlük imza vermiyor.
  Xcode > Settings (Ayarlar) > Apple Accounts > + ile Apple hesabınızla yeniden giriş yapın,
  sonra ./scripts/install.sh komutunu çalıştırın. Uygulamadaki veriler silinmez."
