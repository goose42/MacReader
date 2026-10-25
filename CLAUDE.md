# MacReader

A native macOS app (Swift + SwiftUI) that makes reading easier. Users pick a library folder, add PDFs (converted to plaintext with PDFKit), ebooks (EPUB and Kindle) or web pages, and read them in a minimal Safari-Reader-style view.

## Rules

1. **Branching:** Always create a branch prefixed with `jv.` before making any changes to the repo. Never commit directly to `main`.
2. **TDD:** Always follow red → green → refactor.
   - Red: write a failing test first and run it to see it fail.
   - Green: write the minimum code to make it pass.
   - Refactor: clean up with the tests still green.
   - Commit at each green step.
3. **UI:** All UI changes must adhere to Apple's Human Interface Guidelines for macOS 27. Use system materials, sidebars and toolbars, SF Symbols, semantic fonts and colors, light and dark mode, menu commands and keyboard shortcuts, and accessibility labels.

## Architecture

- `MacReaderKit/` is a local Swift package holding all logic (PDF extraction, text normalization, library storage, view models). Tested with Swift Testing.
- `MacReader/` is the thin SwiftUI app target. Views stay declarative; logic belongs in MacReaderKit.
- `Scripts/generate-ligature-table.sh` regenerates `Structure/CodeLigatureTable.swift` (outline fingerprints of JetBrains Mono's code ligatures) from the font file. PDF generators embed that font with no usable Unicode map, so ligatures like `-->` are recognised by glyph shape rather than text.
- `Scripts/generate-cosmetic-filters.sh` downloads the Fanboy lists and regenerates `Resources/HTML/cosmetic-filters.json` (generic element-hiding rules only) for the HTML junk filter.
- `Scripts/generate-app-icon.sh` crops the icon artwork out of its background and regenerates `MacReader/Assets.xcassets/AppIcon.appiconset`.
- `project.yml` is the XcodeGen spec. The `.xcodeproj` is generated and not committed.

### Library on-disk format

```
<UserChosenFolder>/Items/<uuid>/{original.pdf | original.html | original.epub | original.mobi, content.txt, document.json, metadata.json, position.json, Images/}
```

`document.json` (`ReaderDocument`) is the app-owned structure: headings, paragraphs, callouts (text in a PDF box), tables, images and footnotes in reading order. Paragraphs and headings carry `sentences`, UTF-16 ranges the reader steps through one at a time (abbreviations like "i.e." and "Dr." don't end a sentence); footnotes are their own blocks placed at the end of their section, and callouts, tables, images and footnotes are not reading stops. Tables are recognised from the page's drawing: row separators drawn as one rule per column cell give the columns and rows (`TableDetector`), lines spanning several cells are cut at the column boundaries (`TableSplitter`), and a table that runs onto the next page is merged. The reader and its table of contents render from it; `content.txt` is derived plaintext. The PDF's printed contents page is detected and dropped, and ligature glyphs mis-extracted as capitals ("Dle" for "file") are repaired. Headings carry their section numbers (`numbering`), which the reader shows with a rule before each top-level numbered section. `position.json` holds the reader's cursor (`blockID` + `sentence`), saved on every move and restored when the document is opened; it is kept apart from `document.json` so a rebuild doesn't lose it. Items without `document.json`, or saved with an older `formatVersion`, are rebuilt from `original.pdf` on first open.

### Reader settings

Arrow keys always step sentences once a document is open, even right after clicking the sidebar; ⌥⌘↑/⌥⌘↓ (Go menu) move between documents (`LibraryViewModel.adjacentItem`). **Fixed Highlighting** (on by default) scrolls so the current sentence sits `fixedHighlightLines` lines (1–10) below the top, except near the start and end of the page; `FixedHighlightScroll` does the arithmetic and `ReaderView` measures the sentence through `SentenceHitMap`. With it off the reader keeps the older anchor-based scrolling. The sidebar row of the open document shows a reading-progress ring (`ReadingProgressRing`) fed by `LibraryViewModel.progress(of:)` and `SentenceNavigator.progress`, weighted by sentence length: 0 on the first sentence, 1 on the last. Text, background, highlight and dimmed-text colors each have a light and a dark value (`AppearanceColor`, stored as `light|dark`; a single legacy value applies to both).

### Web pages (HTML)

Saved `.html`/`.htm` pages (optionally with their `…_files` folder, selected together in the importer so the sandbox can read the images) are read by `HTMLTextExtractor` into the same `ReaderDocument`. The item folder holds `original.html` plus a copy of the page's image files under the original `…_files` name; `LibraryItem.sourceKind` is `.html` and `ReaderDocument.metadata` carries byline, site, date, language and source URL.

Pipeline (`MacReaderKit/Sources/MacReaderKit/HTML/`): `HTMLSource` (charset, `_files`, saved-from URL) → `WebPageExtractor` (offscreen `WebPage`, page JS and network off, runs vendored Readability.js plus `junk-filter.js`/`serialize.js` from `Resources/HTML/`, returns an `ExtractionPayload`) → `ContentArbiter` (Readability vs. `article`/`main`/`itemprop=articleBody`, `DensityExtractor`, JSON-LD body, all paragraphs) → `BoilerplateFilter` → `HTMLStructureBuilder` (blocks, images, footnotes) with `MetadataResolver` for the header. JavaScript only reads the rendered page; every decision is pure Swift and tested with `ExtractionPayload` fixtures. WebKit extraction tests run under `swift test`. Page scripts must stay disabled: WebKit then drops `<script>` elements, so JSON-LD is read from the raw HTML. `junk-filter.js` also hides elements matched by generic rules from Fanboy's Annoyance and Cookie Monster lists (CC BY 3.0), generated into `Resources/HTML/cosmetic-filters.json` by `Scripts/generate-cosmetic-filters.sh` from `CosmeticFilterParser`; GPL lists are deliberately not used, and the attribution is in Settings. Tests: `GoldenPageTests` scores whole pages in `Tests/…/Fixtures/HTML/` by token F1 (the `mozilla-*` pages come from Mozilla Readability's test-pages, Apache-2.0). Stale web items throw `LibraryStore.Failure.needsRebuild` and are re-extracted from `original.html`.

### Web pages from a URL

The toolbar **+** is a menu: Add File… or Add Web Page from URL… (⌘L), which opens `AddURLSheet`. `WebAddress` turns what was typed into an http(s) URL (a missing scheme becomes https). `WebPageFetcher` opens it in an offscreen `WebPage` with page scripts **on** and a non-persistent data store, waits for the page to settle, and returns the rendered DOM headed by a `saved from url=` comment, so `HTMLSource.savedFromURL` supplies the source URL. `HTMLTextExtractor.extract(fetched:)` then runs the usual pipeline on that snapshot (still with scripts off): a first pass records which pictures the article asks for, those are downloaded (capped at 60 per page and 10 MB each), and a second pass builds the document. The downloads are saved in `original_files/` with an `images.json` manifest (page address → file) beside `original.html`; `loadImage` reads the manifest, so a stale-format rebuild works offline. `LibraryViewModel.addWebPage` reports failures through `webPageError` for the sheet rather than the library alert; the fetch is injectable (`fetchPage`) so tests never touch the network. Dropping a web address on the library opens the sheet with it filled in.

### Ebooks (EPUB and Kindle)

`EbookExtractor` (`MacReaderKit/Sources/MacReaderKit/Ebook/`) reads a book into the same `ReaderDocument`. It tells the format from the file's contents, not its name: a ZIP, or a folder with `META-INF/container.xml` (an unpacked EPUB, as Apple Books keeps them), is an EPUB; a Palm database of type `BOOKMOBI` is a Kindle book (MOBI, AZW, AZW3, PRC all become `LibraryItem.SourceKind.mobi`). Everything is pure Swift, with no third-party code; the books' markup goes through the web pipeline's `HTMLStructureBuilder`, so lists, tables, code, quotes, images and footnotes behave as they do for web pages.

- **EPUB** (`EPUB/`): `ZipArchive` (stored and deflated entries, ZIP64, CRC-checked) or an unpacked folder → `EPUBContainer` (`container.xml` → OPF) → `EPUBPackage` (Dublin Core with EPUB 3 `refines`, manifest, spine with `linear="no"` last) → `EPUBNavigation` (nav document, else NCX; titles for chapters) → `EPUBExtractor`, which wraps each spine file in a `<section data-mr-chapter="Title">` of one tree. Chapters are read by `XHTMLParser` (Foundation `XMLParser`, XHTML's named entities resolved first) and fall back to WebKit's `WebPageExtractor.serializeBody` when they aren't well-formed. `HTMLStructureBuilder` knows books: `epub:type` footnotes/endnotes (and `doc-footnote` roles) become footnote blocks at the end of their chapter, page-break markers are dropped, and a chapter that doesn't open with a heading gets its title from the contents.
- **Kindle** (`MOBI/`): `PalmDatabase` → `MOBIHeader` (PalmDOC + MOBI header, EXTH metadata) → `MOBIBook` (text records, trailing-data stripping, PalmDOC and Huffman/CDIC decompression). A file with the old format and a KF8 book (EXTH 121 names the KF8 first record, after a `BOUNDARY` record) is read as KF8. Old-format (MOBI 6) text is sloppy HTML read through WebKit: `MOBI6Markup` drops the contents page the `<guide>` points at and marks the headings its `filepos` links address (offsets count bytes), turns `<mbp:pagebreak/>` into rules and `recindex` pictures into `mobi-image:<n>`, and `MOBI6Headings` promotes short paragraphs set entirely in a large `<font size>` (7/6/5 → levels 1/2/3) to headings. KF8 books are rebuilt by `KF8Book`: `MOBIIndex` reads the INDX/TAGX/CTOC indexes (skeleton, fragment, NCX), fragments are inserted into their skeletons (a position inside a tag is moved past it), flows come from the FDST record, and `kindle:embed:`/`kindle:flow:` pictures resolve to `mobi-image:<n>`.
- **DRM**: Adobe/Apple EPUB protection (`encryption.xml` with a non-font algorithm, `rights.xml`, `sinf.xml`) and Kindle encryption (PalmDOC header field) are refused with `EbookExtractor.Failure.drmProtected`; IDPF/Adobe font obfuscation is not DRM and fonts are never read.
- **Library**: `LibraryStore.ingest(ebookAt:extracted:)` keeps the book as `original.epub` (a folder for an unpacked one) or `original.mobi`, with `document.json`, `content.txt` and `Images/` (`book-<n>.<ext>`). Books carry `LibraryItem.author`. Like web pages, a stale `formatVersion` throws `needsRebuild` and the book is re-read from its original on selection. The importer and drop target accept `.epub`, `.mobi`, `.azw`, `.azw3`, `.prc` and unpacked EPUB folders (`LibraryViewModel.canAdd`); the Kindle type is declared in `project.yml` (the generated `MacReader/Info.plist` is git-ignored).
- **Tests**: `Tests/…/Fixtures/Ebook/` holds *Alice's Adventures in Wonderland* (Project Gutenberg #11, public domain) as EPUB 3, MOBI 6 and KF8, and `RealBookTests` checks that all three give exactly the same 26,374 words. Test-only builders (`ZipFixture`, `EPUBFixture`, `PalmFixture`, `MOBIFixture`, `KF8Fixture`, `INDXFixture`, `HuffCDICFixture`) write books in memory. The Huffman/CDIC decoder is verified against `HuffCDICFixture`'s encoder only, since no real Huffman-compressed book is in the fixtures.

## Commands

- Test logic: `swift test --package-path MacReaderKit`
- Generate project: `xcodegen generate`
- Build and test app: `xcodebuild -scheme MacReader -destination 'platform=macOS' build test`
