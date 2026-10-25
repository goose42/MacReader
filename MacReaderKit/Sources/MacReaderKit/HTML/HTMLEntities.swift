import Foundation

/// Decodes the character references (`&#039;`, `&amp;`) that HTML-escaped text such as JSON-LD carries.
enum HTMLEntities {
    private static let named: [String: String] = {
        var table: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "mdash": "—", "ndash": "–",
            "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "trade": "™", "bull": "•",
            "sbquo": "‚", "bdquo": "„", "dagger": "†", "Dagger": "‡", "permil": "‰", "lsaquo": "‹", "rsaquo": "›",
            "euro": "€", "prime": "′", "Prime": "″", "minus": "−", "infin": "∞", "ne": "≠", "le": "≤", "ge": "≥",
            "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "hearts": "♥", "OElig": "Œ", "oelig": "œ",
            "Scaron": "Š", "scaron": "š", "Yuml": "Ÿ", "fnof": "ƒ", "circ": "ˆ", "tilde": "˜", "frasl": "⁄",
            "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "zwnj": "\u{200C}", "zwj": "\u{200D}",
            "lrm": "\u{200E}", "rlm": "\u{200F}",
        ]
        // The Latin-1 block, U+00A0 through U+00FF, in code point order.
        let latin1 = """
            nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr deg plusmn sup2 sup3 acute \
            micro para middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest Agrave Aacute Acirc Atilde Auml Aring \
            AElig Ccedil Egrave Eacute Ecirc Euml Igrave Iacute Icirc Iuml ETH Ntilde Ograve Oacute Ocirc Otilde Ouml \
            times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig agrave aacute acirc atilde auml aring aelig ccedil \
            egrave eacute ecirc euml igrave iacute icirc iuml eth ntilde ograve oacute ocirc otilde ouml divide oslash \
            ugrave uacute ucirc uuml yacute thorn yuml
            """
        for (offset, name) in latin1.split(separator: " ").enumerated() {
            table[String(name)] = String(Character(Unicode.Scalar(UInt8(0xA0 + offset))))
        }
        return table
    }()

    /// One pass only, so `&amp;lt;` becomes `&lt;`. References it doesn't know are left as written.
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text.replacing(/&(#[xX][0-9a-fA-F]+|#[0-9]+|[A-Za-z][A-Za-z0-9]*);/) { match in
            let name = String(match.1)
            if name.hasPrefix("#") {
                let digits = name.dropFirst()
                let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(match.0)
            }
            return named[name] ?? String(match.0)
        }
    }
}
