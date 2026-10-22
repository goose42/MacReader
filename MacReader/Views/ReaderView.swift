import MacReaderKit
import SwiftUI

/// A minimal, read-only reading surface in the spirit of Safari Reader.
struct ReaderView: View {
    let document: ReaderDocument
    @AppStorage("readerFontSize") private var fontSize = 20.0
    @AppStorage("readerColumnWidth") private var columnWidth = ReaderColumnWidth.narrow
    @State private var isShowingContents = false

    var body: some View {
        let sectionBreaks = document.sectionBreaks
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: fontSize * 0.9) {
                    Text(document.title)
                        .font(.system(size: fontSize * 1.8, weight: .bold, design: .serif))
                        .padding(.bottom, fontSize * 0.5)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(document.blocks) { block in
                        VStack(alignment: .leading, spacing: fontSize * 0.9) {
                            if sectionBreaks.contains(block.id) {
                                Divider().padding(.top, fontSize * 1.2)
                            }
                            blockView(block)
                        }
                        .id(block.id)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: columnWidth.maxWidth ?? .infinity, alignment: .leading)
                .padding(.horizontal, columnWidth.horizontalPadding)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .background(.background)
            .navigationTitle(document.title)
            .toolbar {
                ToolbarItemGroup {
                    contentsButton(scrollTo: { id in
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                    })
                    Picker("Column Width", selection: $columnWidth.animation()) {
                        ForEach(ReaderColumnWidth.allCases) { width in
                            Label(width.title, systemImage: width.systemImage).tag(width)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Set text in a narrow column or across the whole window")
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
            headingView(block, font: .system(size: fontSize * headingScale(level), weight: .bold, design: .serif))
                .padding(.top, fontSize * 0.6)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(block.text)
                .font(.system(size: fontSize, design: .serif))
                .lineSpacing(fontSize * 0.4)
        }
    }

    @ViewBuilder
    private func headingView(_ block: ReaderDocument.Block, font: Font) -> some View {
        switch block.numbering {
        case nil:
            Text(block.text).font(font)
        case let numbering? where numbering.placement == .eyebrow:
            VStack(alignment: .leading, spacing: fontSize * 0.2) {
                Text(numbering.label.uppercased())
                    .font(.subheadline.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(block.text).font(font)
            }
        case let numbering?:
            (Text(numbering.label).monospacedDigit().foregroundStyle(.secondary) + Text(" \(block.text)"))
                .font(font)
        }
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
                        title(of: entry)
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

    private func title(of entry: ReaderDocument.TOCEntry) -> Text {
        guard let numbering = entry.numbering else { return Text(entry.title) }
        return Text(numbering.label).monospacedDigit().foregroundStyle(.secondary) + Text(" \(entry.title)")
    }
}
