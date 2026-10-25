# MacReader

A native macOS app that makes reading easier. Pick a library folder, add documents, and read them one sentence at a time in a minimal, Safari-Reader-style view.

## What it reads

- **PDFs**, converted to structured text (headings, paragraphs, tables, figures, footnotes).
- **Ebooks**: EPUB (2 and 3, zipped or an unpacked folder) and Kindle books (MOBI, AZW, AZW3, PRC, in both the old format and KF8). Books protected by DRM can't be opened.
- **Web pages**: saved `.html` files, or any address (⌘L).

## Development

- Test logic: `swift test --package-path MacReaderKit`
- Generate the project: `xcodegen generate`
- Build the app: `xcodebuild -scheme MacReader -destination 'platform=macOS' build`

See `CLAUDE.md` for the architecture.
