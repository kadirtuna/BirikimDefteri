import Foundation

/// Türkiye'deki bankalar ve aracı kurumlar. Saklama yeri ve borç adlarından tanınır; logosu varsa gösterilir,
/// yoksa kurumun renginde baş harf rozeti çizilir.
struct Institution: Identifiable, Hashable, Sendable {
    /// Logo görselinin adı `inst-<id>` olur.
    let id: String
    let name: String
    let color: UInt32
    let monogram: String
    /// `scripts/fetch-logos.py` logoyu bu adresten indirir.
    let domain: String
    /// Adın içinde ardışık kelimeler olarak aranır; en uzun eşleşme kazanır.
    let aliases: [String]

    static func match(_ name: String) -> Institution? {
        let tokens = normalizedTokens(name)
        guard !tokens.isEmpty else { return nil }
        var best: (institution: Institution, length: Int)?
        for institution in all {
            for alias in institution.aliasTokens where alias.count > (best?.length ?? 0) && tokens.containsSequence(alias) {
                best = (institution, alias.count)
            }
        }
        return best?.institution
    }

    static func normalizedTokens(_ text: String) -> [String] {
        text.lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private var aliasTokens: [[String]] { aliases.map(Self.normalizedTokens) }

    static let all: [Institution] = [
        // Kamu bankaları
        Institution(id: "ziraat", name: "Ziraat Bankası", color: 0xE30613, monogram: "Z", domain: "ziraatbank.com.tr", aliases: ["ziraat", "ziraatbank"]),
        Institution(id: "halkbank", name: "Halkbank", color: 0x005BAA, monogram: "H", domain: "halkbank.com.tr", aliases: ["halkbank", "halk bankası"]),
        Institution(id: "vakifbank", name: "VakıfBank", color: 0xFDB913, monogram: "V", domain: "vakifbank.com.tr", aliases: ["vakıfbank", "vakıf bank", "vakıflar bankası", "vakıf"]),
        // Özel bankalar
        Institution(id: "akbank", name: "Akbank", color: 0xDC0005, monogram: "A", domain: "akbank.com", aliases: ["akbank"]),
        Institution(id: "isbank", name: "İş Bankası", color: 0x0A3D8F, monogram: "İş", domain: "isbank.com.tr", aliases: ["iş bankası", "işbank", "işbankası", "işcep"]),
        Institution(id: "garanti", name: "Garanti BBVA", color: 0x00854A, monogram: "G", domain: "garantibbva.com.tr", aliases: ["garanti", "garantibbva"]),
        Institution(id: "yapikredi", name: "Yapı Kredi", color: 0x004B8D, monogram: "YK", domain: "yapikredi.com.tr", aliases: ["yapı kredi", "yapıkredi", "ykb"]),
        Institution(id: "qnb", name: "QNB", color: 0x6D2077, monogram: "Q", domain: "qnb.com.tr", aliases: ["qnb", "finansbank"]),
        Institution(id: "enpara", name: "Enpara", color: 0x7A3E9D, monogram: "e", domain: "enpara.com", aliases: ["enpara"]),
        Institution(id: "denizbank", name: "DenizBank", color: 0x0069B4, monogram: "D", domain: "denizbank.com", aliases: ["denizbank", "deniz bank"]),
        Institution(id: "teb", name: "TEB", color: 0x00A651, monogram: "TEB", domain: "teb.com.tr", aliases: ["teb", "türk ekonomi", "cepteteb"]),
        Institution(id: "ing", name: "ING", color: 0xFF6200, monogram: "ING", domain: "ing.com.tr", aliases: ["ing"]),
        Institution(id: "hsbc", name: "HSBC", color: 0xDB0011, monogram: "H", domain: "hsbc.com.tr", aliases: ["hsbc"]),
        Institution(id: "sekerbank", name: "Şekerbank", color: 0x009639, monogram: "Ş", domain: "sekerbank.com.tr", aliases: ["şekerbank", "şeker bank"]),
        Institution(id: "fibabanka", name: "Fibabanka", color: 0xD5001C, monogram: "F", domain: "fibabanka.com.tr", aliases: ["fibabanka", "fiba"]),
        Institution(id: "odeabank", name: "Odeabank", color: 0x4B2A85, monogram: "O", domain: "odeabank.com.tr", aliases: ["odeabank", "odea"]),
        Institution(id: "anadolubank", name: "Anadolubank", color: 0x003DA5, monogram: "A", domain: "anadolubank.com.tr", aliases: ["anadolubank", "anadolu bank"]),
        Institution(id: "alternatifbank", name: "Alternatif Bank", color: 0xE2001A, monogram: "A", domain: "alternatifbank.com.tr", aliases: ["alternatif bank", "alternatifbank", "abank"]),
        Institution(id: "burgan", name: "Burgan Bank", color: 0x00539B, monogram: "B", domain: "burgan.com.tr", aliases: ["burgan"]),
        Institution(id: "icbc", name: "ICBC Turkey", color: 0xC8102E, monogram: "I", domain: "icbc.com.tr", aliases: ["icbc", "industrial and commercial bank of china"]),
        Institution(id: "turkishbank", name: "Turkish Bank", color: 0x00427A, monogram: "TB", domain: "turkishbank.com", aliases: ["turkish bank", "turkishbank"]),
        Institution(id: "atbank", name: "Arap Türk Bankası", color: 0x00573F, monogram: "AT", domain: "atbank.com.tr", aliases: ["arap türk", "a&t bank", "atbank"]),
        Institution(id: "adabank", name: "Adabank", color: 0x0B5394, monogram: "A", domain: "adabank.com.tr", aliases: ["adabank"]),
        Institution(id: "citibank", name: "Citibank", color: 0x056DAE, monogram: "C", domain: "citibank.com.tr", aliases: ["citibank", "citi"]),
        Institution(id: "deutschebank", name: "Deutsche Bank", color: 0x0018A8, monogram: "DB", domain: "db.com", aliases: ["deutsche bank", "deutsche"]),
        Institution(id: "bankofchina", name: "Bank of China", color: 0xB81C22, monogram: "BC", domain: "bankofchina.com", aliases: ["bank of china"]),
        Institution(id: "mufg", name: "MUFG Bank", color: 0xE60012, monogram: "M", domain: "mufg.jp", aliases: ["mufg"]),
        Institution(id: "jpmorgan", name: "JPMorgan", color: 0x6E4B3A, monogram: "JP", domain: "jpmorgan.com", aliases: ["jpmorgan", "jp morgan"]),
        Institution(id: "intesa", name: "Intesa Sanpaolo", color: 0x00824A, monogram: "IS", domain: "intesasanpaolo.com", aliases: ["intesa"]),
        Institution(id: "habib", name: "Habib Bank", color: 0x00806F, monogram: "HB", domain: "hbl.com", aliases: ["habib bank", "hbl"]),
        Institution(id: "societegenerale", name: "Société Générale", color: 0xE60028, monogram: "SG", domain: "societegenerale.com", aliases: ["société générale"]),
        Institution(id: "colendi", name: "Colendi Bank", color: 0x5A2BE5, monogram: "C", domain: "colendi.com", aliases: ["colendi"]),
        // Katılım bankaları
        Institution(id: "kuveytturk", name: "Kuveyt Türk", color: 0x00845A, monogram: "KT", domain: "kuveytturk.com.tr", aliases: ["kuveyt türk", "kuveytturk"]),
        Institution(id: "albaraka", name: "Albaraka Türk", color: 0x8E1B3B, monogram: "A", domain: "albaraka.com.tr", aliases: ["albaraka", "albarakatürk"]),
        Institution(id: "turkiyefinans", name: "Türkiye Finans", color: 0x0B4EA2, monogram: "TF", domain: "turkiyefinans.com.tr", aliases: ["türkiye finans", "türkiyefinans"]),
        Institution(id: "ziraatkatilim", name: "Ziraat Katılım", color: 0x009B3A, monogram: "ZK", domain: "ziraatkatilim.com.tr", aliases: ["ziraat katılım"]),
        Institution(id: "vakifkatilim", name: "Vakıf Katılım", color: 0x1B8F3A, monogram: "VK", domain: "vakifkatilim.com.tr", aliases: ["vakıf katılım"]),
        Institution(id: "emlakkatilim", name: "Emlak Katılım", color: 0x004F9F, monogram: "EK", domain: "emlakkatilim.com.tr", aliases: ["emlak katılım"]),
        Institution(id: "dunyakatilim", name: "Dünya Katılım", color: 0x0072BC, monogram: "DK", domain: "dunyakatilim.com.tr", aliases: ["dünya katılım"]),
        Institution(id: "hayatfinans", name: "Hayat Finans", color: 0xE4002B, monogram: "HF", domain: "hayatfinans.com.tr", aliases: ["hayat finans"]),
        Institution(id: "tomkatilim", name: "T.O.M. Katılım", color: 0x1F2937, monogram: "TOM", domain: "tomkatilim.com", aliases: ["tom katılım", "t.o.m. katılım"]),
        // Kalkınma ve yatırım bankaları
        Institution(id: "eximbank", name: "Türk Eximbank", color: 0x003B71, monogram: "E", domain: "eximbank.gov.tr", aliases: ["eximbank"]),
        Institution(id: "tskb", name: "TSKB", color: 0x0B3D91, monogram: "T", domain: "tskb.com.tr", aliases: ["tskb", "sınai kalkınma"]),
        Institution(id: "kalkinma", name: "Kalkınma ve Yatırım Bankası", color: 0x00539F, monogram: "KYB", domain: "kalkinma.com.tr", aliases: ["kalkınma ve yatırım", "tkyb"]),
        Institution(id: "ilbank", name: "İller Bankası", color: 0x0D4C92, monogram: "İB", domain: "ilbank.gov.tr", aliases: ["iller bankası", "ilbank"]),
        Institution(id: "aktifbank", name: "Aktif Bank", color: 0x582C83, monogram: "A", domain: "aktifbank.com.tr", aliases: ["aktif bank", "aktifbank", "aktif yatırım bankası"]),
        Institution(id: "nkolay", name: "N Kolay", color: 0x3D1E6D, monogram: "N", domain: "nkolay.com", aliases: ["n kolay", "nkolay"]),
        Institution(id: "nurol", name: "Nurol Yatırım Bankası", color: 0x0F2D69, monogram: "N", domain: "nurolbank.com.tr", aliases: ["nurol"]),
        Institution(id: "pasha", name: "Pasha Yatırım Bankası", color: 0x0D6B5A, monogram: "P", domain: "pashabank.com.tr", aliases: ["pasha"]),
        Institution(id: "bankpozitif", name: "BankPozitif", color: 0xE30613, monogram: "BP", domain: "bankpozitif.com.tr", aliases: ["bankpozitif", "bank pozitif"]),
        // Aracı kurumlar
        Institution(id: "isyatirim", name: "İş Yatırım", color: 0x0A3D8F, monogram: "İY", domain: "isyatirim.com.tr", aliases: ["iş yatırım", "işyatırım"]),
        Institution(id: "akyatirim", name: "Ak Yatırım", color: 0xDC0005, monogram: "AY", domain: "akyatirim.com.tr", aliases: ["ak yatırım", "akyatırım"]),
        Institution(id: "gedik", name: "Gedik Yatırım", color: 0x00468C, monogram: "G", domain: "gedik.com", aliases: ["gedik"]),
        Institution(id: "midas", name: "Midas", color: 0x111827, monogram: "M", domain: "getmidas.com", aliases: ["midas"]),
    ]
}

private extension Array where Element == String {
    func containsSequence(_ sequence: [String]) -> Bool {
        guard !sequence.isEmpty, sequence.count <= count else { return false }
        return (0...(count - sequence.count)).contains { Array(self[$0..<($0 + sequence.count)]) == sequence }
    }
}
