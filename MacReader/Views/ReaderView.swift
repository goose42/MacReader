import MacReaderKit
import SwiftUI

/// A minimal, read-only reading surface in the spirit of Safari Reader.
struct ReaderView: View {
    let document: ReaderDocument
    /// False while the sidebar has keyboard focus, so its arrow keys keep moving the selection.
    let stepsWithArrowKeys: Bool
    @AppStorage("readerFontSize") private var fontSize = 20.0
    @AppStorage("highlightColor") private var highlightColor = HighlightColor.accent
    @State private var isShowingContents = false
    @State private var navigator: SentenceNavigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    init(document: ReaderDocument, stepsWithArrowKeys: Bool = true) {
        self.document = document
        self.stepsWithArrowKeys = stepsWithArrowKeys
        _navigator = State(initialValue: SentenceNavigator(document: document))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: fontSize * 0.9) {
                    Text(document.title)
                        .font(.system(size: fontSize * 1.8, weight: .bold, design: .serif))
                        .padding(.bottom, fontSize * 0.5)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(document.blocks) { block in
                        blockView(block).id(block.id)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .background(.background)
            .focusedSceneValue(\.sentenceNavigation, stepsWithArrowKeys && !isShowingContents
                ? SentenceNavigation(next: { navigator.next() }, previous: { navigator.previous() })
                : nil)
            .onChange(of: document) { navigator = SentenceNavigator(document: document) }
            .onChange(of: navigator.current) { _, position in
                guard let position else { return }
                let scroll = { proxy.scrollTo(position.blockID, anchor: UnitPoint(x: 0.5, y: navigator.scrollAnchor)) }
                if reduceMotion { scroll() } else { withAnimation { scroll() } }
                if let sentence = sentenceText(at: position) {
                    AccessibilityNotification.Announcement(sentence).post()
                }
            }
            .navigationTitle(document.title)
            .toolbar {
                ToolbarItemGroup {
                    contentsButton(scrollTo: { id in
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                    })
                    Button("Smaller Text", systemImage: "textformat.size.smaller") { fontSize = max(14, fontSize - 2) }
                        .keyboardShortcut("-")
                    Button("Larger Text", systemImage: "textformat.size.larger") { fontSize = min(36, fontSize + 2) }
                        .keyboardShortcut("+")
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: ReaderDocument.Block) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(highlighted(block))
                .font(.system(size: fontSize * headingScale(level), weight: .bold, design: .serif))
                .padding(.top, fontSize * 0.6)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(highlighted(block))
                .font(.system(size: fontSize, design: .serif))
                .lineSpacing(fontSize * 0.4)
        case .footnote(let marker):
            HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.5) {
                Text(marker).foregroundStyle(.secondary)
                Text(block.text)
            }
            .font(.system(size: fontSize * 0.8, design: .monospaced))
            .padding(fontSize * 0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Footnote \(marker)")
            .accessibilityValue(block.text)
        }
    }

    /// The block's text with the navigator's current sentence marked, if it falls in this block.
    private func highlighted(_ block: ReaderDocument.Block) -> AttributedString {
        var text = AttributedString(block.text)
        guard let utf16 = navigator.highlight(in: block.id),
              let range = Range(NSRange(location: utf16.lowerBound, length: utf16.count), in: text)
        else { return text }
        text[range].backgroundColor = highlightColor.fill
        if differentiateWithoutColor { text[range].underlineStyle = .single }
        return text
    }

    private func sentenceText(at position: SentenceNavigator.Position) -> String? {
        guard let block = document.blocks.first(where: { $0.id == position.blockID }),
              block.sentences.indices.contains(position.sentence)
        else { return nil }
        let range = block.sentences[position.sentence]
        return (block.text as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
    }

    private func headingScale(_ level: Int) -> Double {
        switch level {
        case 1: 1.5
        case 2: 1.25
        default: 1.1
        }
    }

    private func contentsButton(scrollTo: @escaping (Int) -> Void) -> some View {
        Button("Contents", systemImage: "list.bullet.indent") { isShowingContents.toggle() }
            .help("Show the table of contents")
            .disabled(document.tableOfContents.isEmpty)
            .popover(isPresented: $isShowingContents, arrowEdge: .bottom) {
                ContentsList(entries: document.tableOfContents) { id in
                    isShowingContents = false
                    scrollTo(id)
                }
            }
    }
}

private struct ContentsList: View {
    let entries: [ReaderDocument.TOCEntry]
    let select: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entries) { entry in
                    Button { select(entry.id) } label: {
                        Text(entry.title)
                            .font(entry.level == 1 ? .body.weight(.semibold) : .body)
                            .foregroundStyle(entry.level == 1 ? .primary : .secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .padding(.leading, CGFloat(entry.level - 1) * 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
            }
            .padding(8)
        }
        .frame(width: 320)
        .frame(maxHeight: 420)
    }
}
