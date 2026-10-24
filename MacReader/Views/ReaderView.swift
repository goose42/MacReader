import MacReaderKit
import SwiftUI

/// A minimal, read-only reading surface in the spirit of Safari Reader.
struct ReaderView: View {
    let document: ReaderDocument
    /// False while the sidebar has keyboard focus, so its arrow keys keep moving the selection.
    let stepsWithArrowKeys: Bool
    /// How many pixels of a figure make a point: PDF figures are rendered at 2x, web images are shown at their size.
    let imageScale: Double
    /// The saved copy of the page this document was read from, if it came from the web.
    let originalPageURL: URL?
    /// Where a figure's image file lives, or nil if it is missing.
    let imageURL: (String) -> URL?
    /// Called whenever the reading cursor lands on a new sentence.
    let initialPosition: SentenceNavigator.Position?
    let onPositionChange: (SentenceNavigator.Position) -> Void
    @AppStorage("readerFontSize") private var fontSize = 20.0
    @AppStorage("readerColumnWidth") private var columnWidth = ReaderColumnWidth.narrow
    @AppStorage("highlightColor") private var highlightColor = ColorChoice.automatic
    @AppStorage("dimmedTextColor") private var dimmedTextColor = ColorChoice.automatic
    @AppStorage("dimsSurroundingText") private var dimsSurroundingText = true
    @State private var isShowingContents = false
    @FocusState private var isFocused: Bool
    @State private var navigator: SentenceNavigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    init(
        document: ReaderDocument,
        initialPosition: SentenceNavigator.Position? = nil,
        stepsWithArrowKeys: Bool = true,
        imageScale: Double = 2,
        originalPageURL: URL? = nil,
        imageURL: @escaping (String) -> URL?,
        onPositionChange: @escaping (SentenceNavigator.Position) -> Void = { _ in }
    ) {
        self.document = document
        self.initialPosition = initialPosition
        self.stepsWithArrowKeys = stepsWithArrowKeys
        self.imageScale = imageScale
        self.originalPageURL = originalPageURL
        self.imageURL = imageURL
        self.onPositionChange = onPositionChange
        _navigator = State(initialValue: SentenceNavigator(document: document, startingAt: initialPosition))
    }

    var body: some View {
        let sectionBreaks = document.sectionBreaks
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: fontSize * 0.9) {
                    header
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
                .environment(\.layoutDirection, document.metadata?.isRightToLeft == true ? .rightToLeft : .leftToRight)
                .frame(maxWidth: columnWidth.maxWidth ?? .infinity, alignment: .leading)
                .padding(.horizontal, columnWidth.horizontalPadding)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .background(.background)
            // The arrows are handled here rather than as menu shortcuts, which flash the "Go" menu title on every press.
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { navigator.next(); return .handled }
            .onKeyPress(.upArrow) { navigator.previous(); return .handled }
            .focusedSceneValue(\.sentenceNavigation, stepsWithArrowKeys && !isShowingContents
                ? SentenceNavigation(next: { navigator.next() }, previous: { navigator.previous() })
                : nil)
            .onAppear { restoreScroll(proxy) }
            .onChange(of: document) {
                navigator = SentenceNavigator(document: document, startingAt: initialPosition)
                restoreScroll(proxy)
            }
            .onChange(of: navigator.current) { _, position in
                guard let position else { return }
                onPositionChange(position)
                let scroll = { proxy.scrollTo(position.blockID, anchor: UnitPoint(x: 0.5, y: navigator.scrollAnchor)) }
                if reduceMotion { scroll() } else { withAnimation { scroll() } }
                if let sentence = sentenceText(at: position) {
                    AccessibilityNotification.Announcement(sentence).post()
                }
            }
            .navigationTitle(document.title)
            .toolbar {
                ToolbarItemGroup {
                    if let originalPageURL {
                        Button("Open Original", systemImage: "safari") { NSWorkspace.shared.open(originalPageURL) }
                            .keyboardShortcut("o", modifiers: [.command, .option])
                            .help("Open the saved page in your browser")
                    }
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

    /// The title, and for a web article the site it came from with its byline, date and reading time.
    private var header: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.3) {
            if let siteName = document.metadata?.siteName {
                Text(siteName)
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            Text(document.title)
                .font(.system(size: fontSize * 1.8, weight: .bold, design: .serif))
            if let details = headerDetails {
                Text(details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, fontSize * 0.1)
            }
        }
        .padding(.bottom, fontSize * 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var headerDetails: String? {
        guard let metadata = document.metadata else { return nil }
        var parts: [String] = []
        if let byline = metadata.byline { parts.append(byline) }
        if let date = metadata.publishedDate { parts.append(date.formatted(date: .long, time: .omitted)) }
        if let minutes = document.estimatedReadingMinutes { parts.append("\(minutes) min read") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Brings the saved sentence into view without animation, as the document opens.
    private func restoreScroll(_ proxy: ScrollViewProxy) {
        guard let position = navigator.current, position != SentenceNavigator.Position(blockID: 0, sentence: 0) else { return }
        proxy.scrollTo(position.blockID, anchor: UnitPoint(x: 0.5, y: navigator.scrollAnchor))
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
            sentenceText(block)
                .font(.system(size: fontSize, design: .serif))
                .lineSpacing(fontSize * 0.4)
        case .callout:
            // Boxes that keep the PDF's line breaks are code or tabular, so they get a monospaced face to keep columns and indents aligned.
            Text(block.text)
                .font(.system(size: fontSize * 0.85, design: block.text.contains("\n") ? .monospaced : .default))
                .lineSpacing(fontSize * 0.3)
                .padding(fontSize * 0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                .accessibilityLabel("Boxed text. \(block.text)")
        case .image(let name, let aspectRatio):
            FigureView(url: imageURL(name), aspectRatio: aspectRatio, scale: imageScale)
        case .listItem(let marker, let depth):
            HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.4) {
                Text(marker)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: fontSize * 1.2, alignment: .trailing)
                    .accessibilityHidden(true)
                sentenceText(block)
            }
            .font(.system(size: fontSize, design: .serif))
            .lineSpacing(fontSize * 0.4)
            .padding(.leading, CGFloat(depth) * fontSize * 1.4)
            .accessibilityElement(children: .combine)
        case .quote:
            HStack(alignment: .top, spacing: fontSize * 0.7) {
                Rectangle().fill(.separator).frame(width: 3)
                sentenceText(block)
            }
            .font(.system(size: fontSize, design: .serif).italic())
            .lineSpacing(fontSize * 0.4)
            .padding(.leading, fontSize * 0.5)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Quote. \(block.text)")
        case .code:
            ScrollView(.horizontal) {
                Text(block.text)
                    .font(.system(size: fontSize * 0.8, design: .monospaced))
                    .lineSpacing(fontSize * 0.2)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(fontSize * 0.8)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Code. \(block.text)")
        case .caption:
            Text(block.text)
                .font(.system(size: fontSize * 0.8))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Caption. \(block.text)")
        case .footnote(let marker):
            HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.5) {
                Text(marker).foregroundStyle(.secondary)
                Text(block.text).foregroundStyle(isDimming ? dimmedTextColor.dimmedText : .primary)
            }
            .font(.system(size: fontSize * 0.8, design: .monospaced))
            .padding(fontSize * 0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Footnote \(marker)")
            .accessibilityValue(block.text)
        case .table(let table):
            TableView(table: table, fontSize: fontSize)
        }
    }

    @ViewBuilder
    private func headingView(_ block: ReaderDocument.Block, font: Font) -> some View {
        switch block.numbering {
        case nil:
            sentenceText(block).font(font)
        case let numbering? where numbering.placement == .eyebrow:
            VStack(alignment: .leading, spacing: fontSize * 0.2) {
                Text(numbering.label.uppercased())
                    .font(.subheadline.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                sentenceText(block).font(font)
            }
        case let numbering?:
            (Text(numbering.label).monospacedDigit().foregroundStyle(.secondary) + Text(" ") + Text(highlighted(block), sentences: block.sentences))
                .font(font)
                .onSentenceClick { isFocused = true; navigator.move(to: .init(blockID: block.id, sentence: $0)) }
        }
    }

    /// The block's text, where clicking a sentence moves the reading cursor to it.
    private func sentenceText(_ block: ReaderDocument.Block) -> some View {
        Text(highlighted(block), sentences: block.sentences)
            .onSentenceClick { isFocused = true; navigator.move(to: .init(blockID: block.id, sentence: $0)) }
    }

    /// Whether text outside the current sentence is dimmed, which only makes sense while there is a current sentence.
    private var isDimming: Bool { dimsSurroundingText && navigator.current != nil }

    /// The block's text with the navigator's current sentence marked, if it falls in this block, and the rest dimmed.
    private func highlighted(_ block: ReaderDocument.Block) -> AttributedString {
        var text = AttributedString(block.text)
        if isDimming { text.foregroundColor = dimmedTextColor.dimmedText }
        guard let utf16 = navigator.highlight(in: block.id),
              let range = Range(NSRange(location: utf16.lowerBound, length: utf16.count), in: text)
        else { return text }
        text[range].backgroundColor = highlightColor.highlightFill
        text[range].foregroundColor = .primary
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

/// A table from the PDF: columns share the width, the header row is set off, and rows are separated by hairlines.
private struct TableView: View {
    let table: ReaderDocument.Table
    let fontSize: Double

    private var columnCount: Int { table.rows.map(\.count).max() ?? 0 }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: fontSize * 0.9, verticalSpacing: 0) {
            ForEach(table.rows.indices, id: \.self) { row in
                if row > 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        cell(table.rows[row].indices.contains(column) ? table.rows[row][column] : "", isHeader: table.hasHeader && row == 0)
                    }
                }
                .background(table.hasHeader && row == 0 ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table, \(table.rows.count) rows, \(columnCount) columns")
    }

    private func cell(_ text: String, isHeader: Bool) -> some View {
        Text(text)
            .font(.system(size: fontSize * 0.85, weight: isHeader ? .semibold : .regular))
            .lineSpacing(fontSize * 0.2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, fontSize * 0.6)
            .padding(.vertical, fontSize * 0.45)
            .accessibilityAddTraits(isHeader ? .isHeader : [])
    }
}

/// A picture lifted from the PDF, framed so it reads as separate from the text around it.
private struct FigureView: View {
    let url: URL?
    let aspectRatio: Double
    /// Pixels per point: PDF figures are rendered at 2x, so half their pixel width is their natural size.
    let scale: Double

    var body: some View {
        if let url, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: pixelWidth(of: image) / scale)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Image from the document")
        } else {
            Label("Image unavailable", systemImage: "photo")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

extension FigureView {
    /// The image's width in pixels, whatever resolution its file claims to be.
    fileprivate func pixelWidth(of image: NSImage) -> Double {
        Double(image.representations.map(\.pixelsWide).max() ?? Int(image.size.width))
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
