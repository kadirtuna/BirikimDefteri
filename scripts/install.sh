#!/usr/bin/env bash
# Birikim Defteri'ni bağlı iPhone'a derler, yükler ve başlatır.
# Ücretsiz Apple hesabıyla (Personal Team) imza 7 gün geçerlidir; auto-install.sh bunu kendisi yeniler.
# Derleme telefona bakmaz (genel iOS hedefi); yükleme iPhone kilitliyken de çalışır, aynı Wi-Fi yeterli:
#
#   ./scripts/install.sh
#
# İsteğe bağlı ortam değişkenleri:
#   DEVICE_UDID     Birden fazla iPhone bağlıysa hangisine yükleneceği
#   TEAM_ID         İmza takımı (varsayılan: "Apple Development" sertifikasından okunur)
#   CONFIGURATION   Release (varsayılan) veya Debug
#   SKIP_LAUNCH=1   Yükledikten sonra uygulamayı başlatma (otomatik yenileme bunu kullanır)
#   ONLY_WHEN_LOCKED=1  iPhone'un kilidi açıksa (kullanılıyor olabilir) yükleme; 5 ile çık
#
# Uygulama verileri yeniden yüklemede silinmez. Başarılı yüklemeden sonra imzanın bitiş
# tarihi build/installed-profile-expiry dosyasına yazılır.
#
# Çıkış kodları: 0 tamam, 3 Xcode'da Apple hesabı yok, 4 iPhone bulunamadı ya da ulaşılamadı,
# 5 iPhone kullanımda (yalnızca ONLY_WHEN_LOCKED=1 ile), 6 imza anahtarına o an erişilemedi, 1 diğer.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

SCHEME="BirikimDefteri"
BUNDLE_ID="com.kadirtuna.birikimdefteri"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="build/device"
LOG="build/device-build.log"
STATE="build/installed-profile-expiry"

step() { printf '\n\033[1;32m▸ %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
fail_with() { local code="$1"; shift; printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit "$code"; }

command -v xcodebuild >/dev/null || fail "Xcode bulunamadı. App Store'dan Xcode'u kurun."
mkdir -p build

# Hesap yoksa imza zaten alınamaz; telefonu aramadan ve önbellekteki profili silmeden açık bir mesajla dur.
account_state=0
xcode_account_state || account_state=$?
(( account_state != 1 )) || fail_with "$EXIT_NO_ACCOUNT" "$NO_ACCOUNT_HELP"

# 1. Cihaz
step "Bağlı iPhone aranıyor"
devices_json="$(mktemp)"
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1 || fail "devicectl çalıştırılamadı."

# Çıktı: udid<TAB>ad<TAB>eşleşme<TAB>geliştirici modu
device_line="$(/usr/bin/python3 - "$devices_json" "${DEVICE_UDID:-}" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
wanted = sys.argv[2]
for device in devices:
    hardware = device.get("hardwareProperties", {})
    if hardware.get("reality") != "physical" or hardware.get("platform") != "iOS":
        continue
    if wanted and wanted not in (hardware.get("udid"), device.get("identifier")):
        continue
    print("\t".join([
        hardware.get("udid", ""),
        device.get("deviceProperties", {}).get("name", "iPhone"),
        device.get("connectionProperties", {}).get("pairingState", ""),
        device.get("deviceProperties", {}).get("developerModeStatus", ""),
    ]))
    break
PY
)"

if [[ -z "$device_line" ]]; then
    fail_with "$EXIT_UNREACHABLE" "Bağlı iPhone bulunamadı.
  1. iPhone'u kabloyla Mac'e takın ve kilidini açın.
  2. iPhone'da 'Bu Bilgisayara Güvenilsin mi?' sorusuna Güven deyin.
  3. Xcode > Window > Devices and Simulators'da iPhone'un göründüğünü kontrol edin.
  Sonra bu betiği yeniden çalıştırın."
fi
IFS=$'\t' read -r DEVICE_UDID DEVICE_NAME PAIRING DEV_MODE <<<"$device_line"
[[ "$PAIRING" == "paired" ]] || fail "$DEVICE_NAME bu Mac ile eşleşmemiş. iPhone'da 'Bu Bilgisayara Güven' onayını verin."
if [[ "$DEV_MODE" == "disabled" ]]; then
    fail "$DEVICE_NAME üzerinde Geliştirici Modu kapalı.
  iPhone'da Ayarlar > Gizlilik ve Güvenlik > Geliştirici Modu'nu açın, yeniden başlatın ve 'Aç' deyin."
fi
echo "  $DEVICE_NAME ($DEVICE_UDID)"
echo "$DEVICE_UDID" >build/device-udid

# Yükleme kilitli telefona da yapılır; yalnızca telefona ulaşılabilmesi gerekir.
UNREACHABLE_HELP="$DEVICE_NAME cihazına ulaşılamıyor. Mac ile aynı Wi-Fi'de tutun ya da kabloyla bağlayın."
IN_USE_HELP="$DEVICE_NAME kullanımda (kilidi açık); açık uygulamayı kapatmamak için yükleme sonraya bırakıldı."
check_device() {
    local lock=0
    device_lock_state "$DEVICE_UDID" || lock=$?
    (( lock != 2 )) || fail_with "$EXIT_UNREACHABLE" "$UNREACHABLE_HELP"
    if [[ "${ONLY_WHEN_LOCKED:-}" == "1" ]] && (( lock == 1 )); then
        fail_with "$EXIT_IN_USE" "$IN_USE_HELP"
    fi
    return 0
}
check_device

# 2. İmza takımı
step "İmza kimliği okunuyor"
if [[ -z "${TEAM_ID:-}" ]]; then
    TEAM_ID="$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)"
fi
[[ -n "$TEAM_ID" ]] || fail "Apple Development imza kimliği yok.
  Xcode > Settings > Apple Accounts'ta Apple hesabınızı ekleyin, ardından
  Manage Certificates… > + > Apple Development ile sertifika oluşturun."
echo "  Takım: $TEAM_ID"


# Xcode, süresi dolmamış profili yeniden kullanır; o zaman yükleme süreyi uzatmaz. Önbellekteki
# profil silinince 7 günlük yenisini üretir. Cihazdaki uygulama bundan etkilenmez.
for profile in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision; do
    [[ -f "$profile" ]] || continue
    name="$(security cms -D -i "$profile" 2>/dev/null | plutil -extract Name raw -o - - 2>/dev/null || true)"
    # Uygulamanın ve widget'ın ($BUNDLE_ID.widget) profilleri birlikte yenilenir.
    if [[ "$name" == "iOS Team Provisioning Profile: $BUNDLE_ID" || "$name" == "iOS Team Provisioning Profile: $BUNDLE_ID."* ]]; then
        rm -f "$profile"
    fi
done

# 3. Derleme
# Genel iOS hedefi telefonu beklemez (kilitli iPhone'da geliştirici hizmetleri açılmadığı için cihaz hedefi zaman
# aşımına uğruyordu). Takımın profili kayıtlı bütün cihazları içerir; yeni bir iPhone henüz kayıtlı değilse cihaz
# hedefiyle bir kez daha derlenip kaydedilir (bunun için iPhone'un kilidi açık olmalı).
APP="$BUILD_DIR/Build/Products/$CONFIGURATION-iphoneos/BirikimDefteri.app"
build() {
    xcodebuild -project BirikimDefteri.xcodeproj -scheme "$SCHEME" -configuration "$CONFIGURATION" \
        -destination "$1" -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates ${2:+"$2"} \
        DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic build >"$LOG" 2>&1 && return 0
    grep -E "error:" "$LOG" | sort -u | head -20 >&2 || true
    grep -q "No Accounts" "$LOG" && fail_with "$EXIT_NO_ACCOUNT" "$NO_ACCOUNT_HELP"
    # İmza anahtarına o an erişilemedi (Mac'in ekranı kilitliyken olabiliyor); bir sonraki denemede geçer.
    grep -q "errSecInternalComponent" "$LOG" \
        && fail_with "$EXIT_MAC_BUSY" "İmza anahtarına erişilemedi (Mac'in ekranı kilitli olabilir); sonra yeniden denenecek."
    grep -q -E "needs to be unlocked|Timed out waiting for all destinations" "$LOG" \
        && fail_with "$EXIT_UNREACHABLE" "$DEVICE_NAME bu Mac'te ilk kez kullanılıyor; kaydetmek için kilidini açıp yeniden deneyin."
    fail "Derleme başarısız. Ayrıntılar: $LOG"
}
profile_has_device() {
    local profile; profile="$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null || true)"
    [[ "$profile" == *"<string>$DEVICE_UDID</string>"* ]]
}
step "Derleniyor ($CONFIGURATION)"
build "generic/platform=iOS"
if ! profile_has_device; then
    step "$DEVICE_NAME imza profiline ekleniyor"
    build "id=$DEVICE_UDID" -allowProvisioningDeviceRegistration
fi
[[ -d "$APP" ]] || fail "Derlenen uygulama bulunamadı: $APP"

# 4. Yükleme ve başlatma
step "$DEVICE_NAME cihazına yükleniyor"
check_device   # Derleme sürerken telefon uzaklaşmış ya da kilidi açılmış olabilir.
if ! install_output="$(xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" 2>&1)"; then
    grep -E "ERROR|rror:" <<<"$install_output" | head -5 >&2 || true
    grep -q -i -E "unlock|locked|not connected|unavailable|timed out" <<<"$install_output" \
        && fail_with "$EXIT_UNREACHABLE" "$UNREACHABLE_HELP"
    fail "Yükleme başarısız."
fi

expiry="$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null || true)"
[[ -n "$expiry" ]] && echo "$expiry" >"$STATE"

if [[ "${SKIP_LAUNCH:-}" != "1" ]]; then
    step "Başlatılıyor"
    if ! xcrun devicectl device process launch --device "$DEVICE_UDID" --terminate-existing "$BUNDLE_ID" >/dev/null 2>&1; then
        printf '\n\033[1;33m! Uygulama yüklendi ama başlatılamadı.\033[0m\n'
        echo "  İlk yüklemedeyseniz iPhone'da Ayarlar > Genel > VPN ve Aygıt Yönetimi'nde"
        echo "  geliştirici uygulamasını seçip 'Güven' deyin, sonra simgeye dokunun."
        echo "  iPhone kilitliyse kilidi açıp yeniden deneyin."
    fi
fi

step "Tamam"
[[ -n "$expiry" ]] && echo "  İmza geçerlilik sonu: $expiry"
