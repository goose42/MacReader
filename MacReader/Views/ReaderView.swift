import MacReaderKit
import SwiftUI

/// A minimal, read-only reading surface in the spirit of Safari Reader.
struct ReaderView: View {
    let document: ReaderDocument
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
    @AppStorage("highlightColor") private var highlightColor = AppearanceColor.automatic
    @AppStorage("dimmedTextColor") private var dimmedTextColor = AppearanceColor.automatic
    @AppStorage("textColor") private var textColor = AppearanceColor.automatic
    @AppStorage("backgroundColor") private var backgroundColor = AppearanceColor.automatic
    @AppStorage("dimsSurroundingText") private var dimsSurroundingText = true
    @AppStorage("fixedHighlighting") private var fixedHighlighting = true
    @AppStorage("fixedHighlightLines") private var fixedHighlightLines = FixedHighlightScroll.defaultLines
    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollMetrics = ScrollMetrics()
    @State private var sentenceLayout = SentenceLayout()
    @State private var pendingPlacement: Task<Void, Never>?
    @State private var isShowingContents = false
    @FocusState private var isFocused: Bool
    @State private var navigator: SentenceNavigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    init(
        document: ReaderDocument,
        initialPosition: SentenceNavigator.Position? = nil,
        imageScale: Double = 2,
        originalPageURL: URL? = nil,
        imageURL: @escaping (String) -> URL?,
        onPositionChange: @escaping (SentenceNavigator.Position) -> Void = { _ in }
    ) {
        self.document = document
        self.initialPosition = initialPosition
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
                .foregroundStyle(textChoice.readingText)
                .environment(\.layoutDirection, document.metadata?.isRightToLeft == true ? .rightToLeft : .leftToRight)
                .frame(maxWidth: columnWidth.maxWidth ?? .infinity, alignment: .leading)
                .padding(.horizontal, columnWidth.horizontalPadding)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(
                    offset: geometry.contentOffset.y, viewportHeight: geometry.containerSize.height,
                    contentHeight: geometry.contentSize.height, insetTop: geometry.contentInsets.top,
                    insetBottom: geometry.contentInsets.bottom)
            } action: { _, metrics in
                scrollMetrics = metrics
            }
            .background(backgroundChoice.pageBackground)
            // The arrows are handled here rather than as menu shortcuts, which flash the "Go" menu title on every press.
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { navigator.next(); return .handled }
            .onKeyPress(.upArrow) { navigator.previous(); return .handled }
            .focusedSceneValue(\.sentenceNavigation, !isShowingContents
                ? SentenceNavigation(next: { navigator.next() }, previous: { navigator.previous() })
                : nil)
            .onAppear { isFocused = true; restoreScroll(proxy) }
            .onChange(of: document) {
                navigator = SentenceNavigator(document: document, startingAt: initialPosition)
                isFocused = true
                restoreScroll(proxy)
            }
            .onChange(of: navigator.current) { _, position in
                guard let position else { return }
                onPositionChange(position)
                if reduceMotion { reveal(position, with: proxy) } else { withAnimation { reveal(position, with: proxy) } }
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
        reveal(position, with: proxy)
    }

    /// Scrolls to the sentence: with Fixed Highlighting, to a set number of lines below the top; otherwise to the
    /// sentence's place within its block.
    private func reveal(_ position: SentenceNavigator.Position, with proxy: ScrollViewProxy) {
        pendingPlacement?.cancel()
        guard fixedHighlighting else {
            proxy.scrollTo(position.blockID, anchor: UnitPoint(x: 0.5, y: navigator.scrollAnchor))
            return
        }
        if let target = fixedTarget(for: position) {
            scrollPosition.scrollTo(y: target)
            return
        }
        // The block isn't laid out yet (the stack is lazy, and a tall picture can sit between), so bring it on screen
        // and place the sentence once its position has settled. Until then the block would be left at the top.
        proxy.scrollTo(position.blockID, anchor: .top)
        pendingPlacement = Task {
            var previous: Double?
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }
                guard let target = fixedTarget(for: position) else { continue }
                if let previous, abs(previous - target) < 0.5 {
                    scrollPosition.scrollTo(y: target)
                    return
                }
                previous = target
            }
        }
    }

    /// The scroll offset that places the sentence, or nil when its layout isn't known yet.
    private func fixedTarget(for position: SentenceNavigator.Position) -> Double? {
        guard let layout = sentenceLayout.layout(of: position.blockID, sentence: position.sentence) else { return nil }
        let metrics = scrollMetrics
        let target = FixedHighlightScroll.targetOffset(
            sentenceTop: layout.top - metrics.insetTop,
            lineHeight: layout.lineHeight + fontSize * 0.4,
            lines: fixedHighlightLines,
            currentOffset: metrics.offset + metrics.insetTop,
            viewportHeight: metrics.viewportHeight - metrics.insetTop - metrics.insetBottom,
            contentHeight: metrics.contentHeight)
        return target - metrics.insetTop
    }

    private var textChoice: ColorChoice { textColor.resolved(colorScheme) }
    private var backgroundChoice: ColorChoice { backgroundColor.resolved(colorScheme) }
    private var highlightChoice: ColorChoice { highlightColor.resolved(colorScheme) }
    private var dimmedChoice: ColorChoice { dimmedTextColor.resolved(colorScheme) }

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
                Text(block.text).foregroundStyle(isDimming ? dimmedChoice.dimmedText : textChoice.readingText)
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
                .trackingSentences(of: block, in: sentenceLayout) { select($0, in: block) }
        }
    }

    /// The block's text, where clicking a sentence moves the reading cursor to it.
    private func sentenceText(_ block: ReaderDocument.Block) -> some View {
        Text(highlighted(block), sentences: block.sentences)
            .trackingSentences(of: block, in: sentenceLayout) { select($0, in: block) }
    }

    private func select(_ sentence: Int, in block: ReaderDocument.Block) {
        isFocused = true
        navigator.move(to: .init(blockID: block.id, sentence: sentence))
    }

    /// Whether text outside the current sentence is dimmed, which only makes sense while there is a current sentence.
    private var isDimming: Bool { dimsSurroundingText && navigator.current != nil }

    /// The block's text with the navigator's current sentence marked, if it falls in this block, and the rest dimmed.
    private func highlighted(_ block: ReaderDocument.Block) -> AttributedString {
        var text = AttributedString(block.text)
        if isDimming { text.foregroundColor = dimmedChoice.dimmedText }
        guard let utf16 = navigator.highlight(in: block.id),
              let range = Range(NSRange(location: utf16.lowerBound, length: utf16.count), in: text)
        else { return text }
        text[range].backgroundColor = highlightChoice.highlightFill
        text[range].foregroundColor = textChoice.readingText
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

/// How far the reader is scrolled, for placing the current sentence.
private struct ScrollMetrics: Equatable {
    var offset = 0.0
    var viewportHeight = 0.0
    var contentHeight = 0.0
    var insetTop = 0.0
    var insetBottom = 0.0
}

/// Where the sentences of the blocks on screen were laid out, in the scroll view's coordinates.
/// A reference type that the views write to as they lay out, so recording a frame doesn't redraw anything.
@MainActor
private final class SentenceLayout {
    private struct Entry {
        let map: SentenceHitMap
        var top: Double?
    }
    private var entries: [Int: Entry] = [:]

    func map(for blockID: Int) -> SentenceHitMap {
        if let entry = entries[blockID] { return entry.map }
        let map = SentenceHitMap()
        entries[blockID] = Entry(map: map)
        return map
    }

    func setTop(_ top: Double, for blockID: Int) { entries[blockID]?.top = top }
    func forget(_ blockID: Int) { entries[blockID] = nil }

    /// The top of the sentence's first line and that line's height, or nil if its block isn't on screen.
    func layout(of blockID: Int, sentence: Int) -> (top: Double, lineHeight: Double)? {
        guard let entry = entries[blockID], let top = entry.top, let line = entry.map.firstLine(of: sentence) else { return nil }
        return (top + line.minY, line.height)
    }
}

extension View {
    /// Selects the clicked sentence and reports where the block's sentences sit, for Fixed Highlighting.
    fileprivate func trackingSentences(
        of block: ReaderDocument.Block, in layout: SentenceLayout, select: @escaping (Int) -> Void
    ) -> some View {
        onSentenceClick(map: layout.map(for: block.id), select)
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: {
                layout.setTop($0, for: block.id)
            }
            .onDisappear { layout.forget(block.id) }
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
