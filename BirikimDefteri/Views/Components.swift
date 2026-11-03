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
                TextField(placeholder, text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                if let suffix {
                    Text(suffix).foregroundStyle(.secondary)
                }
            }
        }
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
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Bitti") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
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
