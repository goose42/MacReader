// Regenerates MacReaderKit/Sources/MacReaderKit/Resources/HTML/cosmetic-filters.json from ad-blocker filter lists.
// Run via Scripts/generate-cosmetic-filters.sh, which downloads the lists.
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: generate <output.json> <list.txt>...\n".utf8))
    exit(1)
}
let lists = arguments.dropFirst(2).compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
let filters = CosmeticFilterParser.parse(lists: lists)
try filters.json.write(to: URL(fileURLWithPath: arguments[1]))
print("classes: \(filters.classes.count), ids: \(filters.ids.count), compound: \(filters.complex.values.reduce(0) { $0 + $1.count })")
