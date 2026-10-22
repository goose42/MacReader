import MacReaderKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("highlightColor") private var highlightColor = HighlightColor.accent

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
            LabeledContent("Preview") {
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(.system(.body, design: .serif))
                    .padding(.horizontal, 4)
                    .background(highlightColor.fill, in: RoundedRectangle(cornerRadius: 3))
                    .accessibilityLabel("Highlight preview")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
