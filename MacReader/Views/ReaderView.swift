import SwiftUI

/// A minimal, read-only reading surface in the spirit of Safari Reader.
struct ReaderView: View {
    let title: String
    let text: String
    @AppStorage("readerFontSize") private var fontSize = 20.0

    private var paragraphs: [String] {
        text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: fontSize * 0.9) {
                Text(title)
                    .font(.system(size: fontSize * 1.8, weight: .bold, design: .serif))
                    .padding(.bottom, fontSize * 0.5)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: fontSize, design: .serif))
                        .lineSpacing(fontSize * 0.4)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup {
                Button("Smaller Text", systemImage: "textformat.size.smaller") { fontSize = max(14, fontSize - 2) }
                    .keyboardShortcut("-")
                Button("Larger Text", systemImage: "textformat.size.larger") { fontSize = min(36, fontSize + 2) }
                    .keyboardShortcut("+")
            }
        }
    }
}
