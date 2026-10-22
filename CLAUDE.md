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
- `project.yml` is the XcodeGen spec. The `.xcodeproj` is generated and not committed.

### Library on-disk format

```
<UserChosenFolder>/Items/<uuid>/{original.pdf, content.txt, document.json, metadata.json, Images/}
```

`document.json` (`ReaderDocument`) is the app-owned structure: headings, paragraphs, callouts (text in a PDF box), tables and images in reading order. Tables are recognised from the page's drawing: row separators drawn as one rule per column cell give the columns and rows (`TableDetector`), lines spanning several cells are cut at the column boundaries (`TableSplitter`), and a table that runs onto the next page is merged. The reader and its table of contents render from it; `content.txt` is derived plaintext. The PDF's printed contents page is detected and dropped, and ligature glyphs mis-extracted as capitals ("Dle" for "file") are repaired. Headings carry their section numbers (`numbering`), which the reader shows with a rule before each top-level numbered section. Items without `document.json`, or saved with an older `formatVersion`, are rebuilt from `original.pdf` on first open.

## Commands

- Test logic: `swift test --package-path MacReaderKit`
- Generate project: `xcodegen generate`
- Build and test app: `xcodebuild -scheme MacReader -destination 'platform=macOS' build test`
