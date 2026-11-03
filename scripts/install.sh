#!/usr/bin/env bash
# Birikim Defteri'ni bağlı iPhone'a derler, yükler ve başlatır.
# Ücretsiz Apple hesabıyla (Personal Team) imza 7 gün geçerlidir; haftada bir çalıştırın:
#
#   ./scripts/install.sh
#
# İsteğe bağlı ortam değişkenleri:
#   DEVICE_UDID     Birden fazla iPhone bağlıysa hangisine yükleneceği
#   TEAM_ID         İmza takımı (varsayılan: "Apple Development" sertifikasından okunur)
#   CONFIGURATION   Release (varsayılan) veya Debug
#   SKIP_LAUNCH=1   Yükledikten sonra uygulamayı başlatma (otomatik yenileme bunu kullanır)
#
# Uygulama verileri yeniden yüklemede silinmez. Başarılı yüklemeden sonra imzanın bitiş
# tarihi build/installed-profile-expiry dosyasına yazılır.
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="BirikimDefteri"
BUNDLE_ID="com.kadirtuna.birikimdefteri"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="build/device"
LOG="build/device-build.log"
STATE="build/installed-profile-expiry"

step() { printf '\n\033[1;32m▸ %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

command -v xcodebuild >/dev/null || fail "Xcode bulunamadı. App Store'dan Xcode'u kurun."
mkdir -p build

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
    fail "Bağlı iPhone bulunamadı.
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
xcrun devicectl --timeout 30 device info lockState --device "$DEVICE_UDID" >/dev/null 2>&1 \
    || fail "$DEVICE_NAME cihazına ulaşılamıyor. Kabloyla bağlayın ya da Mac ile aynı Wi-Fi'de olduğundan emin olun."

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
    if [[ "$name" == "iOS Team Provisioning Profile: $BUNDLE_ID" ]]; then
        rm -f "$profile"
    fi
done

# 3. Derleme
step "Derleniyor ($CONFIGURATION)"
if ! xcodebuild -project BirikimDefteri.xcodeproj -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination "id=$DEVICE_UDID" -derivedDataPath "$BUILD_DIR" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic \
    build >"$LOG" 2>&1; then
    grep -E "error:" "$LOG" | sort -u | head -20 >&2 || true
    fail "Derleme başarısız. Ayrıntılar: $LOG"
fi
APP="$BUILD_DIR/Build/Products/$CONFIGURATION-iphoneos/BirikimDefteri.app"
[[ -d "$APP" ]] || fail "Derlenen uygulama bulunamadı: $APP"

# 4. Yükleme ve başlatma
step "$DEVICE_NAME cihazına yükleniyor"
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" >/dev/null

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
