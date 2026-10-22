import MacReaderKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("highlightColor") private var highlightColor = HighlightColor.accent
    @AppStorage("dimsSurroundingText") private var dimsSurroundingText = true

    var body: some View {
        Form {
            LabeledContent("Sentence Highlight") {
                HStack {
                    ColorPicker(
                        "Sentence Highlight",
                        selection: Binding(get: { highlightColor.color }, set: { highlightColor = HighlightColor($0) }),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    Button("Use Accent Color") { highlightColor = .accent }
                        .disabled(highlightColor == .accent)
                }
            }
            Toggle("Dim Surrounding Text", isOn: $dimsSurroundingText)
            LabeledContent("Preview") {
                Text(preview)
                    .font(.system(.body, design: .serif))
                    .accessibilityLabel("Highlight preview")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var preview: AttributedString {
        var text = AttributedString("Text around it. The current sentence. More text after.")
        if dimsSurroundingText { text.foregroundColor = .secondary }
        if let range = text.range(of: "The current sentence.") {
            text[range].backgroundColor = highlightColor.fill
            text[range].foregroundColor = .primary
        }
        return text
    }
}
