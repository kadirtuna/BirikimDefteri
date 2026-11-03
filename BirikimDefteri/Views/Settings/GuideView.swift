import SwiftUI

/// Kılavuzdaki bir konu: ne işe yaradığı, uygulamada nerede olduğu ve ayrıntıları.
struct GuideTopic: Identifiable {
    struct Item: Identifiable {
        let title: String
        let text: String
        var id: String { title }
    }

    let title: String
    let symbol: String
    let tint: Color
    let summary: String
    let location: String
    let items: [Item]

    var id: String { title }

    func matches(_ query: String) -> Bool {
        let fields = [title, summary, location] + items.flatMap { [$0.title, $0.text] }
        return fields.contains { $0.localizedStandardContains(query) }
    }
}

struct GuideSection: Identifiable {
    let title: String
    let topics: [GuideTopic]
    var id: String { title }
}

/// Uygulamanın özelliklerini anlatan kılavuz; Ayarlar'dan açılır.
struct GuideView: View {
    @State private var query = ""

    var body: some View {
        let query = query.trimmed
        let sections = query.isEmpty ? GuideContent.sections : GuideContent.sections.compactMap { section in
            let topics = section.topics.filter { $0.matches(query) }
            return topics.isEmpty ? nil : GuideSection(title: section.title, topics: topics)
        }

        List {
            if query.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Birikim Defteri; altın, döviz, fon ve TL birikimlerinizi kimin adına, nerede ve ne maliyetle durduklarıyla birlikte takip eder.")
                        Text("Bir konuya dokunarak ne işe yaradığını, uygulamada nerede olduğunu ve nasıl kullanıldığını görebilirsiniz.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 4)
                }
            }

            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.topics) { topic in
                        NavigationLink {
                            GuideTopicView(topic: topic)
                        } label: {
                            GuideTopicRow(topic: topic)
                        }
                    }
                }
            }
        }
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Kılavuzda ara")
        .navigationTitle("Kullanım kılavuzu")
    }
}

private struct GuideIcon: View {
    let topic: GuideTopic
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: topic.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(topic.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct GuideTopicRow: View {
    let topic: GuideTopic

    var body: some View {
        HStack(spacing: 12) {
            GuideIcon(topic: topic)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                Text(topic.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct GuideTopicView: View {
    let topic: GuideTopic

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    GuideIcon(topic: topic, size: 44)
                    Text(topic.summary)
                }
                .padding(.vertical, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Uygulamada nerede", systemImage: "location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(topic.location)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }

            ForEach(topic.items) { item in
                Section(item.title) {
                    Text(item.text)
                        .font(.subheadline)
                        .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum GuideContent {
    static let sections: [GuideSection] = [
        GuideSection(title: "Başlarken", topics: [
            GuideTopic(
                title: "Temel kavramlar",
                symbol: "book.closed.fill",
                tint: Theme.green,
                summary: "Kişi, ürün, saklama yeri ve işlem; bakiyelerin nasıl hesaplandığı.",
                location: "Ayarlar > Tanımlar",
                items: [
                    .init(title: "Kişi", text: "Varlığın kime ait olduğu. Kişileri Ayarlar > Kişiler'den ekleyip adlarını değiştirebilirsiniz. Özet ve Analiz'deki kişi seçiciyle herkesi ya da tek bir kişiyi görürsünüz."),
                    .init(title: "Ürün", text: "Takip ettiğiniz şey: gram altın, çeyrek altın, gümüş, dolar, euro, fon, TL… Her ürünün bir birimi (gr, adet, $, €, ₺) ve türü vardır. Ayarlar > Ürünler'den yeni ürün ekleyebilirsiniz."),
                    .init(title: "Saklama yeri", text: "Varlığın durduğu yer: Fiziki (elde), bir banka ya da aracı kurum. Ayarlar > Saklama yerleri'nden yönetilir."),
                    .init(title: "İşlem", text: "Her alış, satış ve aktarım bir işlemdir. Bakiyeler ayrıca saklanmaz; her zaman işlemlerden kişi, ürün ve yer bazında hesaplanır. Bu yüzden bir işlemi düzelttiğinizde bütün toplamlar kendiliğinden düzelir."),
                    .init(title: "Ortalama maliyet", text: "Aynı ürünü farklı fiyatlarla aldığınızda maliyetiniz ortalamaya göre tutulur. Satışta, satılan miktarın ortalama maliyeti düşülür; satış tutarıyla arasındaki fark gerçekleşen kâr ya da zarardır."),
                ]
            ),
        ]),
        GuideSection(title: "Kayıt", topics: [
            GuideTopic(
                title: "Alış ve satış",
                symbol: "plus",
                tint: Theme.positive,
                summary: "Yeni alım ya da satım girme, düzenleme, silme ve filtreleme.",
                location: "Özet ya da Kayıtlar > sağ üstteki + > Alış / Satış",
                items: [
                    .init(title: "Kayıt ekleme", text: "İşlem türünü, ürünü, kişiyi, yeri, miktarı ve birim fiyatı girin. Birim fiyatı boş bırakırsanız güncel fiyat kullanılır. TL'de yalnızca tutar girilir."),
                    .init(title: "Elde olmayan satılamaz", text: "Bir kişinin bir yerde sahip olduğundan fazlası satılamaz. Daha sonraki bir satışı karşılıksız bırakacak bir düzenleme ya da silme de engellenir; uygulama nedenini yazar."),
                    .init(title: "Düzenleme ve silme", text: "Kayıtlar'da bir satıra dokunarak düzenleyin, sola kaydırarak silin. Silmeden sonra ekranın altında birkaç saniye Geri al düğmesi görünür."),
                    .init(title: "Filtre", text: "Kayıtlar'ın sol üstündeki filtre düğmesiyle ürüne, yere ve kişiye göre süzebilirsiniz."),
                ]
            ),
            GuideTopic(
                title: "Aktarım",
                symbol: "arrow.left.arrow.right",
                tint: .blue,
                summary: "Bir varlığı bir yerden ötekine, satış yapmadan taşıma.",
                location: "Özet ya da Kayıtlar > sağ üstteki + > Aktarım",
                items: [
                    .init(title: "Ne işe yarar", text: "Örneğin evdeki altını bankadaki altın hesabına koyduğunuzda ya da parayı bir bankadan ötekine taşıdığınızda. Satış ve yeniden alış girmeniz gerekmez."),
                    .init(title: "Maliyet", text: "Aktarım kâr ya da zarar doğurmaz. Ürün, çıktığı yerdeki ortalama maliyetiyle birlikte taşınır; böylece getiri hesabınız bozulmaz."),
                    .init(title: "Nasıl girilir", text: "Ürünü, kişiyi, nereden ve nereye taşındığını, miktarı ve tarihi seçin. Tümünü aktar düğmesi o yerdeki bütün miktarı doldurur."),
                    .init(title: "Kayıtlarda", text: "Aktarım tek satır olarak görünür: Aktarım · kişi · nereden → nereye. Dokunarak düzenleyebilir ya da silebilirsiniz."),
                ]
            ),
        ]),
        GuideSection(title: "Takip ve analiz", topics: [
            GuideTopic(
                title: "Özet",
                symbol: "chart.pie.fill",
                tint: Theme.gold,
                summary: "Net varlık, dağılım, hedefler ve varlıklarınızın nerede olduğu.",
                location: "Özet",
                items: [
                    .init(title: "Net varlık kartı", text: "Varlıklar, borçlar, net varlık ve kâr/zarar tek kartta. En üstteki kişi seçiciyle herkesi ya da tek bir kişiyi görebilirsiniz; açılışta Ben seçilidir."),
                    .init(title: "Dağılım", text: "Halka grafik varlıkları Ürün, Tür, Kişi ya da Yer'e göre gruplar. Listedeki bir satıra dokununca o grubun değer geçmişini, fiyat geçmişini, nerede ve kimde durduğunu, alım ve satımlarını görürsünüz."),
                    .init(title: "Varlıklarım nerede?", text: "Bu kart her banka, aracı kurum ve fiziki yerdeki ürünleri, toplamı ve toplam içindeki payı gösterir."),
                    .init(title: "Fiyatı girilmemiş ürünler", text: "Fiyatı olmayan ürünler toplamlara katılmaz ve ayrı bir bölümde listelenir. Dokunup fiyat girebilirsiniz."),
                ]
            ),
            GuideTopic(
                title: "Analiz",
                symbol: "chart.xyaxis.line",
                tint: Theme.green,
                summary: "Değer geçmişi, dolar ve altın karşılığı, getiri ve temel göstergeler.",
                location: "Özet > sol üstteki grafik simgesi ya da Son 6 ay kartı",
                items: [
                    .init(title: "Değer ve maliyet", text: "Varlıklarınızın değeri ile maliyeti aynı grafikte. Dönem olarak 3A, 6A, 1Y ya da Tümü seçilebilir. Grafiğe dokunup parmağınızı kaydırarak herhangi bir günün değerini görebilirsiniz."),
                    .init(title: "₺, $ ya da gram altın", text: "Birim seçiciyle aynı geçmişi dolar ya da gram altın cinsinden görebilirsiniz. TL değeriniz artarken dolar ya da altın karşılığı yerinde sayıyorsa artışın kaynağı enflasyon ve kurdur, gerçek bir büyüme değildir."),
                    .init(title: "Temel göstergeler", text: "Toplam değer, yatırılan tutar (maliyet), gerçekleşmemiş ve gerçekleşen kâr/zarar, borç/varlık oranı ve aylık taksit toplamı."),
                    .init(title: "Tür dağılımı (zaman içinde)", text: "Altın, döviz, TL gibi türlerin toplam içindeki payının zaman içindeki değişimi."),
                    .init(title: "Aylık alım ve satım", text: "Her ay ne kadarlık alım ve satım yaptığınız."),
                    .init(title: "Alış maliyetinize göre getiri", text: "Her ürünün bugünkü fiyatının sizin ortalama alış fiyatınıza göre değişimi; yani elinizdeki malın getirisi. Ürünün piyasa fiyatının belli bir dönemdeki değişimi, ürün ayrıntısında ayrıca gösterilir."),
                    .init(title: "Gerçekleşen kâr/zarar", text: "Satışlarınızda ortaya çıkan kâr ya da zarar; son 10 satış listelenir."),
                ]
            ),
            GuideTopic(
                title: "Aylık rapor",
                symbol: "doc.richtext.fill",
                tint: .purple,
                summary: "Bir ayın tek sayfalık PDF özeti; paylaşılabilir ya da kaydedilebilir.",
                location: "Analiz > sağ üstteki rapor simgesi",
                items: [
                    .init(title: "İçerik", text: "Ay başı ve ay sonu değer, aylık değişim, ay içindeki alım ve satımlar, gerçekleşen kâr/zarar, borç, net varlık, son 12 ayın grafiği, tür dağılımı ve ay içindeki işlemler tek bir A4 sayfasında."),
                    .init(title: "Oluşturma ve paylaşma", text: "Son 12 aydan birini seçip PDF oluştur'a, ardından Paylaş ya da kaydet'e dokunun. Dosyayı Dosyalar'a kaydedebilir, e-postayla ya da mesajla gönderebilirsiniz."),
                    .init(title: "Kişi seçimi", text: "Rapor, Analiz'de seçili kişi için hazırlanır. Tutarları gizle açık olsa bile raporda gerçek rakamlar yer alır."),
                ]
            ),
            GuideTopic(
                title: "Hedefler",
                symbol: "target",
                tint: Theme.gold,
                summary: "Net varlık ya da ürün miktarı hedefi; ilerleme ve tahmini tarih.",
                location: "Özet > Hedefler kartı ya da Ayarlar > Hedefler",
                items: [
                    .init(title: "Hedef türleri", text: "Net varlık (varlıklar eksi borçlar) ya da bir ürünün miktarı, örneğin 100 gr altın. İsterseniz hedefi tek bir kişiye bağlayabilirsiniz."),
                    .init(title: "İlerleme ve tahmini tarih", text: "Yüzde ve çubuk bugünkü durumu gösterir. Tahmini tarih, son 3 aydaki ilerleme hızınız sürerse hedefe ne zaman ulaşacağınızı söyler; son 3 ayda ilerleme yoksa tarih verilmez."),
                    .init(title: "Düzenleme", text: "Hedefler ekranında bir hedefe dokunarak düzenleyin, sola kaydırarak silin. Özet'te ilk 3 hedef görünür."),
                ]
            ),
        ]),
        GuideSection(title: "Fiyatlar ve borçlar", topics: [
            GuideTopic(
                title: "Fiyatlar",
                symbol: "tag.fill",
                tint: Theme.gold,
                summary: "İnternetten güncel fiyat, elle fiyat girme ve piyasa değişimi.",
                location: "Fiyatlar",
                items: [
                    .init(title: "İnternetten güncelleme", text: "Altın ve gümüş Truncgil Finans'tan (Kapalıçarşı alış fiyatı), dolar ve euro TCMB döviz alış kurundan alınır. Güncelle düğmesi ya da listeyi aşağı çekmek fiyatları yeniler. Ayarlar'da otomatik güncelleme açıksa uygulama, son güncellemenin üzerinden bir saat geçtiyse açılışta kendiliğinden yeniler."),
                    .init(title: "Elle fiyat", text: "Yeni değeri yazıp sağ üstteki Kaydet'e dokunun; yalnızca değiştirdiğiniz fiyatlar kaydedilir. Fon gibi otomatik olmayan ürünlerin fiyatını siz girersiniz. Otomatik ürünlerde elle girdiğiniz fiyat bir sonraki internet güncellemesine kadar geçerlidir."),
                    .init(title: "Neden alış fiyatı", text: "Değerleme alış fiyatıyla yapılır; bugün satsanız elinize geçecek tutarı gösterir."),
                    .init(title: "Piyasa değişimi", text: "Her ürünün altında son 1 aydaki fiyat değişimi yazar. Ürün ayrıntısındaki Fiyat geçmişi bölümü, kaydedilen fiyatlara göre piyasanın değişimini gösterir; bu, sizin alış maliyetinize göre getiriden ayrıdır."),
                ]
            ),
            GuideTopic(
                title: "Borçlar",
                symbol: "creditcard.fill",
                tint: Theme.negative,
                summary: "Kredi ve kart borçları, ödeme geçmişi, tahmini bitiş ve hatırlatmalar.",
                location: "Borçlar",
                items: [
                    .init(title: "Borç ekleme", text: "Sağ üstteki + ile kredi, kredi kartı ya da başka bir borç ekleyin: kurum, kalan tutar, aylık taksit, son ödeme ya da bitiş tarihi, taksit günü ve kişi."),
                    .init(title: "Genel bakış", text: "En üstte toplam borç, türlere göre ara toplamlar ve aylık taksit toplamı yer alır; borçlar kuruma göre gruplanır. Borçlar Özet'teki net varlıktan düşülür."),
                    .init(title: "Ödeme ve plan", text: "Bir borca dokunup Ödeme ekle ile yaptığınız ödemeyi girin. Tutar kalan borçtan düşülür; kredi kartında son ödeme tarihi bir ay ileri alınır. Detay ekranında ödeme geçmişi, toplam ödenen ve krediler için tahmini bitiş (kalan taksit sayısı) görünür. Tahmin faizi hesaba katmaz."),
                    .init(title: "Hatırlatmalar", text: "Ayarlar > Bildirimler > Ödeme hatırlatmaları açıkken kredi kartında son ödemeden 2 gün önce ve o gün, kredide her ay taksit gününde saat 09:00'da bildirim gelir. Taksit günü borcun Düzenle ekranından seçilir. Tutarları gizle açıksa bildirimde tutar yazmaz."),
                ]
            ),
        ]),
        GuideSection(title: "Güvenlik ve veriler", topics: [
            GuideTopic(
                title: "Kilit ve gizlilik",
                symbol: "faceid",
                tint: Theme.green,
                summary: "Face ID kilidi, tutarları gizleme ve verilerin nerede durduğu.",
                location: "Ayarlar > Güvenlik",
                items: [
                    .init(title: "Face ID kilidi", text: "Uygulama her açılışta ve arka plandan her dönüşte Face ID ister; Face ID olmazsa iPhone şifrenizle açabilirsiniz. Kilit kapatılamaz. Uygulama değiştiricide içerik gizlenir."),
                    .init(title: "Tutarları gizle", text: "Özet'in sol üstündeki göz simgesiyle ya da Ayarlar > Tutarları gizle ile açılıp kapanır. Açıkken bütün tutarlar ₺•••• olarak görünür; yanınızda biri varken işe yarar."),
                    .init(title: "Verileriniz", text: "Bütün veriler yalnızca bu iPhone'da durur. Hesap, sunucu ya da analitik yoktur; internete yalnızca güncel fiyatları almak için çıkılır."),
                ]
            ),
            GuideTopic(
                title: "Geri al ve işlem geçmişi",
                symbol: "clock.arrow.circlepath",
                tint: .blue,
                summary: "Yapılan her değişikliğin kaydı ve geri alınması.",
                location: "Ayarlar > İşlem geçmişi",
                items: [
                    .init(title: "Ne kaydedilir", text: "İşlem, aktarım, borç ve borç ödemelerindeki her ekleme, düzenleme ve silme. Son 500 değişiklik saklanır ve günlere göre listelenir."),
                    .init(title: "Geri alma", text: "Bir değişikliğin yanındaki Geri al'a dokunun; kayıt değişiklikten önceki hâline döner. Geri alma sonraki bir satışı karşılıksız bırakacaksa engellenir ve nedeni yazılır. Kayıtlar'da silmeden sonra çıkan Geri al da aynı işi görür."),
                ]
            ),
            GuideTopic(
                title: "Yedekleme ve dışa aktarma",
                symbol: "externaldrive.fill",
                tint: .gray,
                summary: "Otomatik ve elle yedek, Excel'e aktarma ve imza yenileme.",
                location: "Ayarlar > Excel'e aktar ve Yedekleme",
                items: [
                    .init(title: "Otomatik yedek", text: "Veriler her değiştiğinde uygulama kendi klasörüne tarihli bir yedek yazar ve son 30'unu tutar. Mac'teki zamanlanmış görev bunları iCloud Drive > Birikim Defteri Yedekleri klasörüne kopyalar."),
                    .init(title: "Elle yedek", text: "Yedeği dışa aktar ile bir JSON dosyası kaydedin. Yedekten geri yükle mevcut bütün verilerin yerine geçer ve geri alınamaz; önce mevcut veriyi yedeklemeniz önerilir."),
                    .init(title: "Excel'e aktar", text: "İşlemler, varlıklar ve borçlar ayrı CSV dosyaları olarak kaydedilir ve Excel'de doğrudan açılır: noktalı virgülle ayrılmış, ondalıklar virgüllü."),
                    .init(title: "İmza yenileme", text: "Ücretsiz Apple hesabıyla uygulamanın imzası 7 gün geçerlidir. Mac'teki görev, iPhone aynı ağdayken imzayı süresi dolmadan yeniler; verileriniz silinmez."),
                ]
            ),
        ]),
    ]
}
