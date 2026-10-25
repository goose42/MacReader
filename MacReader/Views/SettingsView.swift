import MacReaderKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("readerColumnWidth") private var columnWidth = ReaderColumnWidth.narrow
    @AppStorage("highlightColor") private var highlightColor = ColorChoice.automatic
    @AppStorage("dimsSurroundingText") private var dimsSurroundingText = true
    @AppStorage("dimmedTextColor") private var dimmedTextColor = ColorChoice.automatic

    var body: some View {
        Form {
            Picker("Column Width", selection: $columnWidth) {
                ForEach(ReaderColumnWidth.allCases) { width in
                    Text(width.title).tag(width)
                }
            }
            .pickerStyle(.segmented)
            colorRow("Sentence Highlight", choice: $highlightColor, automatic: .accentColor, resetTitle: "Use Accent Color")
            Toggle("Dim Surrounding Text", isOn: $dimsSurroundingText)
            colorRow("Dimmed Text", choice: $dimmedTextColor, automatic: .secondary, resetTitle: "Use Default")
                .disabled(!dimsSurroundingText)
            LabeledContent("Preview") {
                Text(preview)
                    .font(.system(.body, design: .serif))
                    .accessibilityLabel("Highlight preview")
            }
            Section("Acknowledgements") {
                acknowledgement(
                    "Mozilla Readability", detail: "Finds the article in saved web pages. Apache License 2.0.",
                    url: "https://github.com/mozilla/readability")
                acknowledgement(
                    "Fanboy’s Annoyance and Cookie Monster lists", detail: "Hide popups, banners and cookie notices on saved web pages. CC BY 3.0.",
                    url: "https://easylist.to/pages/licence.html")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func acknowledgement(_ name: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let destination = URL(string: url) { Link(name, destination: destination) } else { Text(name) }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func colorRow(_ title: String, choice: Binding<ColorChoice>, automatic: Color, resetTitle: String) -> some View {
        LabeledContent(title) {
            HStack {
                ColorPicker(
                    title,
                    selection: Binding(
                        get: { choice.wrappedValue.color(automatic: automatic) },
                        set: { choice.wrappedValue = ColorChoice($0) }),
                    supportsOpacity: false
                )
                .labelsHidden()
                Button(resetTitle) { choice.wrappedValue = .automatic }
                    .disabled(choice.wrappedValue == .automatic)
            }
        }
    }

    private var preview: AttributedString {
        var text = AttributedString("Text around it. The current sentence. More text after.")
        if dimsSurroundingText { text.foregroundColor = dimmedTextColor.dimmedText }
        if let range = text.range(of: "The current sentence.") {
            text[range].backgroundColor = highlightColor.highlightFill
            text[range].foregroundColor = .primary
        }
        return text
    }
}
