# Birikim Defteri: Claude için proje notları

Bu dosya herkese açık depoda durur; kişisel ya da finansal bilgi içermez. Kişisel bağlam (cihaz, takım,
kullanıcının verileri, yarım kalan işler) git dışındaki `.claude/context.local.md` dosyasındadır.
**Çalışmaya başlamadan önce onu da oku.**

@context.local.md

## Proje

Kişisel iPhone birikim takibi: altın, gümüş, döviz, fon ve TL; kimde, nerede, ne maliyetle.
SwiftUI + SwiftData + Swift Charts + WidgetKit + App Intents, iOS 17+, Swift 5 modu, üçüncü taraf paket yok.
Arayüz Türkçe, biçimler `tr_TR` (₺1.234,50). Para ve miktar her yerde `Decimal`, SwiftData'da metin olarak saklanır.
Uygulama App Store'a çıkmaz; ücretsiz Apple hesabıyla (Personal Team) imzalanıp kullanıcının kendi iPhone'una yüklenir.
Depo: `~/Developer/BirikimDefteri`, GitHub'da herkese açık: `kadirtuna/BirikimDefteri` (MIT, README İngilizce + Türkçe).

## Kullanıcıyla çalışma kuralları

- Konuşma Türkçe. Kullanıcı önerileri seçilebilir liste (checklist) olarak görmeyi seviyor.
- Apple hesap şifresini **asla** isteme ve hiçbir yere girme. Xcode'a hesap eklemek, iPhone'da "Güven" demek kullanıcının işi.
- Bir şey kurman gerekirse (Homebrew paketi vb.) önce sor. Üçüncü taraf paket ekleme.
- Veriler cihazda kalır. Ağa yalnızca herkese açık fiyat kaynakları için çıkılır; yeni bir adres eklemek gizlilik
  kararıdır: kullanıcıya söyle, README'deki gizlilik bölümünü güncelle.
- **Değerleme ilkesi:** gösterilen değer, bozdurulunca ele geçecek tutardan asla fazla olmamalı. Her bakiye durduğu
  yerin alış fiyatıyla değerlenir (aşağıya bak). Yeni bir değerleme kaynağı eklerken bu ilkeyi koru.
- Simülatör olarak iPhone 14 kullan (silinmişse `xcrun simctl create "iPhone 14" com.apple.CoreSimulator.SimDeviceType.iPhone-14 <runtime>`).
- Kullanıcı telefonu kabloyla bağlayınca söylenmesini bekler: işi bitirince "telefonu bağlayabilirsin" de.

## Herkese açık depo: sızıntı kuralları

- Kişisel ya da finansal veri, kişi adları, tutarlar, e-posta, imza takım kimliği, cihaz UDID'si **asla** commit edilmez.
  Commit'ten önce `git diff --cached` üzerinde tarama yap (bağlam dosyasındaki adlar ve kimliklerle).
- `project.pbxproj` içinde `DEVELOPMENT_TEAM = ""` kalır; takım derlemede `install.sh` tarafından verilir.
- Git yazarı: `GIT_AUTHOR_EMAIL` ve `GIT_COMMITTER_EMAIL` = `70758836+kadirtuna@users.noreply.github.com`.
  Commit mesajı Türkçe, sonunda `Co-Authored-By` satırı.
- Yalnızca `main` pushlanır. Yerel `ozel-gecmis` dalı ilk geliştirme geçmişini (kişisel bilgilerle) tutar: **asla pushlama.**
- Banka logoları (`BirikimDefteri/InstitutionLogos.xcassets/`) tescilli marka; git dışında, `scripts/fetch-logos.py` ile
  yerelde indirilir. README ekran görüntüleri logosuz bir derlemeyle alınır.
- Her yeni özellikte README'nin iki dili, uygulama içi kılavuz (`Views/Settings/GuideView.swift`) ve README'deki test
  sayısı güncellenir.

## Komutlar

```bash
# Testler (paralel test kapalı: açıkken her çalıştırmada simülatör klonlanıp disk doluyor)
xcodebuild test -project BirikimDefteri.xcodeproj -scheme BirikimDefteri \
  -destination 'platform=iOS Simulator,name=iPhone 14' -parallel-testing-enabled NO -derivedDataPath build/sim

# Bağlı iPhone'a derle, yükle, başlat (takımı sertifikadan okur, 7 günlük profili yeniler)
./scripts/install.sh

# Otomatik imza yenileme ve yedek çekme (launchd, saatte bir)
./scripts/auto-install.sh [--force | --enable | --disable]   # kayıt: ~/Library/Logs/BirikimDefteri/auto-install.log
```

Debug derlemede açılış argümanları: `-demoData` (örnek veri, verinin yerine geçer, kilidi atlar), `-startTab prices`
(`records`, `debts`, `settings`), `-expandInstitutions YES`, `-widgetPreview YES` (widget'ın bütün boyutları).
Örnek veriyle simülatörde: `xcrun simctl launch booted com.kadirtuna.birikimdefteri -demoData -startTab prices`.

## Mimari

- `Core/` (yalnızca Foundation; widget de kullanır): `LedgerTypes` (tipler), `PortfolioCalculator` (saf hesaplama:
  ortalama maliyet, aktarımlar, satış doğrulama, gruplama, değer geçmişi, yer dökümü, günlük değişim, hedef, borç planı),
  `Format` (tr_TR, tutar gizleme, `parseDecimal`, yazarken binlik ayraç), `Quotes` (genel fiyat anahtarları, Truncgil/TCMB/
  CoinGecko ayrıştırma), `BidQuotes` (kurum alış fiyatları, doviz.com tablo ayrıştırıcısı), `PriceBoard` (kurumların alış ve
  satış tablosu, `SharedStore`), `Institutions` (54 banka ve aracı kurum, ad eşleştirme).
- `Models/`: SwiftData modelleri (Person, Location, Asset, PricePoint, TransactionRecord, Debt, DebtPayment, Goal,
  JournalEntry), `Ledger` (sorgulardan kurulan anlık görüntü, ortamda `\.ledger`), `Journal` (değişiklik geçmişi ve geri al),
  `Backup` (JSON yedek, geri yükleme, birleştirme), `AutoBackup`, `PriceUpdater`, `PaymentReminders`, `Exporters` (CSV),
  `DemoData` (yalnızca Debug).
- `Views/`: Özet, Kayıtlar, Borçlar, Fiyatlar, Ayarlar, Analiz ekranları.
- `App/`: giriş noktası (`AppContainer.shared`), `RootView`, `AppLock` (zorunlu Face ID / cihaz şifresi), `Intents`
  (Siri ve Kısayollar: "Birikim Defteri ile alım ekle"), `WidgetPreview` (Debug).
- `BirikimDefteriWidget/`: "Kurum fiyatları" widget'ı; `Core/` dosyalarını ve logo kataloğunu uygulamayla paylaşır
  (`project.pbxproj` içindeki file-system-synchronized exception set'ler).
- `scripts/`: `install.sh`, `auto-install.sh`, `lib.sh` (ortak; Xcode hesap kontrolü, çıkış kodları 3/4),
  `fetch-logos.py` + `normalize-logo.swift`, `app-icon.swift` (simge ve koyu/renkli sürümleri).
- Xcode projesi elle yazılmıştır (objectVersion 77, PBXFileSystemSynchronizedRootGroup); yeni dosya klasöre konunca
  derlemeye girer. Hedef eklemek için `project.pbxproj` elle düzenlenir.

### Önemli kararlar

- Bakiyeler hiç saklanmaz; her zaman işlemlerden hesaplanır. Aktarım iki kayıttır (`transferOut`/`transferIn`,
  ortak `transferID`), maliyet ortalama maliyetle taşınır.
- Fiyatlar: genel fiyat (`PricePoint.locationID == nil`) Truncgil (Kapalıçarşı alış), TCMB (döviz alış), CoinGecko (XAUT).
  Yere özel alış fiyatı (`PricePoint.locationID` dolu) doviz.com karşılaştırma tablolarından: bankada o bankanın alışı,
  fiziki yerde büyük kuyumcuların (Kapalıçarşı, Altınkaynak, Harem, Odacı, Venüs) en düşük alışı, Midas'ta XAUT ×
  0,995 (%0,20 komisyon + %0,30 fark payı), tanınmayan bankada bütün bankaların en düşüğü. Kurum fiyatı alınamazsa
  genel fiyata olan son fark korunur.
- Silmeler ve yedekten geri yüklemeler işlem geçmişinden hiç budanmaz (Silinenler); ekleme/düzenleme son 500.
- Ücretsiz hesap kısıtları: imza 7 gün; App Group yok, bu yüzden uygulama ile widget ortak **Anahtar Zinciri grubu**
  (`*.entitlements`, `SharedStore`) kullanır; widget'ın ayrı App ID'si ve profili var (`.widget`).
  Xcode'da Apple hesabı çıkış yaparsa imza yenilenemez (`install.sh` 3 ile çıkar). İmza bir kez dolarsa iPhone
  geliştiriciye güveni sıfırlar: Ayarlar > Genel > VPN ve Aygıt Yönetimi'nden yeniden "Güven" gerekir.

## Telefondaki veriyle çalışma

- Veri deposu: uygulama kapsayıcısında `Library/Application Support/default.store` (+ `-wal`, `-shm`). Yüklemeden ya da
  veri değişikliğinden önce `xcrun devicectl device copy from ... --domain-type appDataContainer --domain-identifier
  com.kadirtuna.birikimdefteri` ile yedekle; sonra `sqlite3` ile kayıt sayılarını karşılaştırarak doğrula.
- Telefondaki veriyi Mac'ten düzeltmek: yedek biçimindeki bir JSON'u `Documents/BirikimDefteri-ekle.json` olarak kopyala
  ve uygulamayı yeniden başlat; kişi/yer/ürün adla eşleşir, aynı kimlikli işlem ve borçlar güncellenir. Sonuç
  `Documents/BirikimDefteri-ekle-sonuc.txt`'ye yazılır. Bu yol İşlem geçmişi'ne **kaydedilmez**; kullanıcıya söyle.
- Otomatik JSON yedekleri telefonda `Documents/Yedekler` (son 30); Mac görevi iCloud Drive > Birikim Defteri Yedekleri'ne çeker.
