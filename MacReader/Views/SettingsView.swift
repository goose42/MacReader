import MacReaderKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("readerColumnWidth") private var columnWidth = ReaderColumnWidth.narrow
    @AppStorage("fixedHighlighting") private var fixedHighlighting = true
    @AppStorage("fixedHighlightLines") private var fixedHighlightLines = FixedHighlightScroll.defaultLines
    @AppStorage("textColor") private var textColor = AppearanceColor.automatic
    @AppStorage("backgroundColor") private var backgroundColor = AppearanceColor.automatic
    @AppStorage("highlightColor") private var highlightColor = AppearanceColor.automatic
    @AppStorage("dimsSurroundingText") private var dimsSurroundingText = true
    @AppStorage("dimmedTextColor") private var dimmedTextColor = AppearanceColor.automatic

    var body: some View {
        Form {
            Section("Reading") {
                Picker("Column Width", selection: $columnWidth) {
                    ForEach(ReaderColumnWidth.allCases) { width in
                        Text(width.title).tag(width)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Fixed Highlighting", isOn: $fixedHighlighting)
                    .help("Scrolls so the current sentence stays at the same height, keeping your eyes in one place.")
                Stepper(
                    "Lines from Top: \(fixedHighlightLines)", value: $fixedHighlightLines, in: FixedHighlightScroll.lineRange
                )
                .disabled(!fixedHighlighting)
                Toggle("Dim Surrounding Text", isOn: $dimsSurroundingText)
            }
            Section("Colors") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                        Text("Light").font(.subheadline).foregroundStyle(.secondary)
                        Text("Dark").font(.subheadline).foregroundStyle(.secondary)
                        Text("")
                    }
                    colorRow("Text", color: $textColor)
                    colorRow("Background", color: $backgroundColor)
                    colorRow("Sentence Highlight", color: $highlightColor)
                    colorRow("Dimmed Text", color: $dimmedTextColor)
                        .disabled(!dimsSurroundingText)
                }
                HStack(spacing: 12) {
                    preview(.light)
                    preview(.dark)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Light and dark previews")
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
        .frame(width: 520)
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

    /// One setting with a picker for each appearance and a button that puts both back to automatic.
    private func colorRow(_ title: String, color: Binding<AppearanceColor>) -> some View {
        GridRow {
            Text(title)
            picker("\(title), light", choice: Binding(get: { color.wrappedValue.light }, set: { color.wrappedValue.light = $0 }), scheme: .light)
            picker("\(title), dark", choice: Binding(get: { color.wrappedValue.dark }, set: { color.wrappedValue.dark = $0 }), scheme: .dark)
            Button("Reset \(title) Colors", systemImage: "arrow.counterclockwise") { color.wrappedValue = .automatic }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Use the automatic \(title.lowercased()) colors")
                .disabled(color.wrappedValue == .automatic)
        }
    }

    private func picker(_ label: String, choice: Binding<ColorChoice>, scheme: ColorScheme) -> some View {
        ColorPicker(
            label,
            selection: Binding(
                get: { choice.wrappedValue.color(automatic: automatic(for: label, scheme: scheme)) },
                set: { choice.wrappedValue = ColorChoice($0) }),
            supportsOpacity: false
        )
        .labelsHidden()
        .environment(\.colorScheme, scheme)
    }

    /// What "automatic" looks like for a setting in an appearance, so the picker opens on the color in use.
    private func automatic(for label: String, scheme: ColorScheme) -> Color {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        func resolve(_ color: NSColor) -> Color {
            var result = Color.clear
            appearance?.performAsCurrentDrawingAppearance { result = Color(nsColor: color) }
            return result
        }
        if label.hasPrefix("Background") { return resolve(.textBackgroundColor) }
        if label.hasPrefix("Dimmed") { return resolve(.secondaryLabelColor) }
        if label.hasPrefix("Sentence") { return resolve(.controlAccentColor) }
        return resolve(.labelColor)
    }

    /// The sample text as the reader would draw it in one appearance.
    private func preview(_ scheme: ColorScheme) -> some View {
        let isDark = scheme == .dark
        let text = textColor.choice(isDark: isDark).readingText
        var sample = AttributedString("Text around it. The current sentence. More text after.")
        sample.foregroundColor = dimsSurroundingText ? dimmedTextColor.choice(isDark: isDark).dimmedText : text
        if let range = sample.range(of: "The current sentence.") {
            sample[range].backgroundColor = highlightColor.choice(isDark: isDark).highlightFill
            sample[range].foregroundColor = text
        }
        return Text(sample)
            .font(.system(.body, design: .serif))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor.choice(isDark: isDark).pageBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .environment(\.colorScheme, scheme)
            .accessibilityLabel("\(isDark ? "Dark" : "Light") preview")
    }
}
