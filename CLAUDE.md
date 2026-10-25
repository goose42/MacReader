# MacReader

A native macOS app (Swift + SwiftUI) that makes reading easier. Users pick a library folder, add PDFs, which are converted to plaintext with PDFKit, and read them in a minimal Safari-Reader-style view.

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
<UserChosenFolder>/Items/<uuid>/{original.pdf, content.txt, document.json, metadata.json, position.json, Images/}
```

`document.json` (`ReaderDocument`) is the app-owned structure: headings, paragraphs, callouts (text in a PDF box), tables, images and footnotes in reading order. Paragraphs and headings carry `sentences`, UTF-16 ranges the reader steps through one at a time (abbreviations like "i.e." and "Dr." don't end a sentence); footnotes are their own blocks placed at the end of their section, and callouts, tables, images and footnotes are not reading stops. Tables are recognised from the page's drawing: row separators drawn as one rule per column cell give the columns and rows (`TableDetector`), lines spanning several cells are cut at the column boundaries (`TableSplitter`), and a table that runs onto the next page is merged. The reader and its table of contents render from it; `content.txt` is derived plaintext. The PDF's printed contents page is detected and dropped, and ligature glyphs mis-extracted as capitals ("Dle" for "file") are repaired. Headings carry their section numbers (`numbering`), which the reader shows with a rule before each top-level numbered section. `position.json` holds the reader's cursor (`blockID` + `sentence`), saved on every move and restored when the document is opened; it is kept apart from `document.json` so a rebuild doesn't lose it. Items without `document.json`, or saved with an older `formatVersion`, are rebuilt from `original.pdf` on first open.

### Web pages (HTML)

Saved `.html`/`.htm` pages (optionally with their `…_files` folder, selected together in the importer so the sandbox can read the images) are read by `HTMLTextExtractor` into the same `ReaderDocument`. The item folder holds `original.html` plus a copy of the page's image files under the original `…_files` name; `LibraryItem.sourceKind` is `.html` and `ReaderDocument.metadata` carries byline, site, date, language and source URL.

Pipeline (`MacReaderKit/Sources/MacReaderKit/HTML/`): `HTMLSource` (charset, `_files`, saved-from URL) → `WebPageExtractor` (offscreen `WebPage`, page JS and network off, runs vendored Readability.js plus `junk-filter.js`/`serialize.js` from `Resources/HTML/`, returns an `ExtractionPayload`) → `ContentArbiter` (Readability vs. `article`/`main`/`itemprop=articleBody`, `DensityExtractor`, JSON-LD body, all paragraphs) → `BoilerplateFilter` → `HTMLStructureBuilder` (blocks, images, footnotes) with `MetadataResolver` for the header. JavaScript only reads the rendered page; every decision is pure Swift and tested with `ExtractionPayload` fixtures. WebKit extraction tests run under `swift test`. Page scripts must stay disabled: WebKit then drops `<script>` elements, so JSON-LD is read from the raw HTML. `junk-filter.js` also hides elements matched by generic rules from Fanboy's Annoyance and Cookie Monster lists (CC BY 3.0), generated into `Resources/HTML/cosmetic-filters.json` by `Scripts/generate-cosmetic-filters.sh` from `CosmeticFilterParser`; GPL lists are deliberately not used, and the attribution is in Settings. Tests: `GoldenPageTests` scores whole pages in `Tests/…/Fixtures/HTML/` by token F1 (the `mozilla-*` pages come from Mozilla Readability's test-pages, Apache-2.0). Stale web items throw `LibraryStore.Failure.needsRebuild` and are re-extracted from `original.html`.

### Web pages from a URL

The toolbar **+** is a menu: Add File… or Add Web Page from URL… (⌘L), which opens `AddURLSheet`. `WebAddress` turns what was typed into an http(s) URL (a missing scheme becomes https). `WebPageFetcher` opens it in an offscreen `WebPage` with page scripts **on** and a non-persistent data store, waits for the page to settle, and returns the rendered DOM headed by a `saved from url=` comment, so `HTMLSource.savedFromURL` supplies the source URL. `HTMLTextExtractor.extract(fetched:)` then runs the usual pipeline on that snapshot (still with scripts off): a first pass records which pictures the article asks for, those are downloaded (capped at 60 per page and 10 MB each), and a second pass builds the document. The downloads are saved in `original_files/` with an `images.json` manifest (page address → file) beside `original.html`; `loadImage` reads the manifest, so a stale-format rebuild works offline. `LibraryViewModel.addWebPage` reports failures through `webPageError` for the sheet rather than the library alert; the fetch is injectable (`fetchPage`) so tests never touch the network. Dropping a web address on the library opens the sheet with it filled in.

## Commands

- Test logic: `swift test --package-path MacReaderKit`
- Generate project: `xcodegen generate`
- Build and test app: `xcodebuild -scheme MacReader -destination 'platform=macOS' build test`
