import SwiftUI

struct PersonFilterPicker: View {
    let people: [Person]
    @Binding var selection: PersonFilter

    var body: some View {
        if people.count <= 3 {
            picker.pickerStyle(.segmented)
        } else {
            picker.pickerStyle(.menu)
        }
    }

    private var picker: some View {
        Picker("Kişi", selection: $selection) {
            Text("Herkes").tag(PersonFilter.everyone)
            ForEach(people) { person in
                Text(person.name).tag(PersonFilter.person(person.id))
            }
        }
    }
}

/// "+₺1.234,50" ve isteğe bağlı "+%5,2"; kârda yeşil, zararda kırmızı.
struct ProfitText: View {
    let profit: Decimal
    let ratio: Decimal?
    var showsRatio = true

    var body: some View {
        Text(text)
            .foregroundStyle(profit > 0 ? Theme.positive : profit < 0 ? Theme.negative : Color.secondary)
            .monospacedDigit()
    }

    private var text: String {
        var text = Format.signedLira(profit)
        if showsRatio, let ratio {
            text += " (\(Format.signedPercent(ratio)))"
        }
        return text
    }
}

/// Sağa yaslı, ondalık klavyeli tutar/miktar alanı.
struct DecimalField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var suffix: String?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                DecimalTextField(placeholder: placeholder, text: $text, accessibilityLabel: title)
                if let suffix {
                    Text(suffix).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Yazarken binlik ayraç ekleyen ("1.234,50"), sağa yaslı, ondalık klavyeli alan.
/// Biçimlendirme UITextField'ın düzenleme adımında yapılır: SwiftUI TextField'da metni sonradan değiştirmek
/// hızlı yazarken tuş kaybettiriyordu. İmlecin sağındaki rakamlar korunur, böylece ortadan düzenleme de çalışır.
struct DecimalTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isInvalid = false
    var accessibilityLabel: String?

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .decimalPad
        field.textAlignment = .right
        field.adjustsFontForContentSizeCategory = true
        field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedDigitSystemFont(ofSize: 17, weight: .regular))
        field.delegate = context.coordinator
        // SwiftUI'nin klavye çubuğu UIKit alanına bağlanmıyor; "Bitti" diğer alanlardaki gibi solda.
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        toolbar.items = [
            UIBarButtonItem(title: "Bitti", primaryAction: UIAction { [weak field] _ in field?.resignFirstResponder() }),
            .flexibleSpace(),
        ]
        toolbar.sizeToFit()
        field.inputAccessoryView = toolbar
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        // Dışarıdan gelen değer (ör. düzenlenen kaydın tutarı) ayraçlı gösterilir; okunan sayı aynı kalır.
        let shown = Format.groupedInput(text, previous: "")
        if field.text != shown, field.text != text { field.text = shown }
        field.placeholder = placeholder
        field.textColor = isInvalid ? .systemRed : .label
        field.accessibilityLabel = accessibilityLabel
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DecimalTextField

        init(_ parent: DecimalTextField) {
            self.parent = parent
        }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = field.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let raw = current.replacingCharacters(in: swiftRange, with: string)
            let formatted = Format.groupedInput(raw, previous: current)

            // İmleç: değişiklikten sonra sağında kalan rakam ve virgül sayısı korunur.
            let caret = min(range.location + (string as NSString).length, (raw as NSString).length)
            let trailing = (raw as NSString).substring(from: caret).filter { $0.isNumber || $0 == "," }.count
            var position = formatted.count
            var seen = 0
            for character in formatted.reversed() where seen < trailing {
                position -= 1
                if character.isNumber || character == "," { seen += 1 }
            }

            field.text = formatted
            if let caretPosition = field.position(from: field.beginningOfDocument, offset: position) {
                field.selectedTextRange = field.textRange(from: caretPosition, to: caretPosition)
            }
            parent.text = formatted
            return false
        }
    }
}

/// Yeni kayıtlarda son kullanılan kişi ve yer.
enum RecentChoices {
    private static let personKey = "lastPersonID"
    private static let locationKey = "lastLocationID"

    static func person(among ids: [UUID]) -> UUID? { stored(personKey, among: ids) }
    static func location(among ids: [UUID]) -> UUID? { stored(locationKey, among: ids) }

    static func remember(personID: UUID, locationID: UUID) {
        UserDefaults.standard.set(personID.uuidString, forKey: personKey)
        UserDefaults.standard.set(locationID.uuidString, forKey: locationKey)
    }

    private static func stored(_ key: String, among ids: [UUID]) -> UUID? {
        guard let text = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: text), ids.contains(id) else { return nil }
        return id
    }
}

struct ErrorLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Theme.negative)
    }
}

extension View {
    /// Ondalık klavyede dönüş tuşu olmadığı için klavyenin üstüne "Bitti" ekler.
    /// Ondalık klavyede "Bitti" düğmesi. Yeni iOS'ta düğme klavyenin üstünde yüzdüğü için solda durur;
    /// sağa yaslı tutar alanının üstüne binip yazılanı örtmesin.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Bitti") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                Spacer()
            }
        }
    }
}

extension Binding where Value == Bool {
    /// İsteğe bağlı bir değerin varlığını bir uyarının görünürlüğüne bağlar.
    init<Wrapped>(isPresent value: Binding<Wrapped?>) {
        self.init(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } }
        )
    }
}

/// "Tutarları gizle" ayarı. Biçimlendiriciyi hemen günceller, ayarı saklar; kök görünüm yeniden çizilir.
enum AmountPrivacy {
    static let key = "hideAmounts"

    static func set(_ hidden: Bool) {
        Format.hidesAmounts = hidden
        UserDefaults.standard.set(hidden, forKey: key)
    }
}
