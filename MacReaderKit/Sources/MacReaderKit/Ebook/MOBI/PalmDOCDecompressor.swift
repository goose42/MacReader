import Foundation

/// PalmDOC compression, the scheme most MOBI books use: literals, short verbatim runs, back-references into the text
/// already produced, and a one-byte form for a space followed by a letter.
enum PalmDOCDecompressor {
    enum Failure: Error, Equatable { case corrupt }

    /// A run that is cut short keeps what it has, since a text record may end mid-token; a back-reference to text that
    /// doesn't exist is an error.
    static func decompress(_ data: Data) throws -> Data {
        let input = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(input.count * 2)

        var index = 0
        while index < input.count {
            let byte = input[index]
            index += 1
            switch byte {
            case 0x00, 0x09...0x7F:
                output.append(byte)
            case 0x01...0x08:
                let end = min(index + Int(byte), input.count)
                output.append(contentsOf: input[index..<end])
                index = end
            case 0xC0...0xFF:
                output.append(0x20)
                output.append(byte ^ 0x80)
            default:
                guard index < input.count else { return Data(output) }
                let pair = Int(byte) << 8 | Int(input[index])
                index += 1
                let distance = (pair >> 3) & 0x7FF
                let length = (pair & 0x7) + 3
                guard distance > 0, distance <= output.count else { throw Failure.corrupt }
                for _ in 0..<length { output.append(output[output.count - distance]) }
            }
        }
        return Data(output)
    }
}
