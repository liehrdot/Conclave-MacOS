/// Mana symbols in costs and rules text ("{2}{B}{G}", "{T}: Add {G}."), split into text and symbols so the app can
/// draw them like on the cards. The same rules as the iPhone app's `Mana` (Conclave-iOS ConclaveCore), which mirror
/// `symbol()`, `mana()` and `rulesText()` in the web app's `util.js`; here VoiceOver's words come from the app, so
/// they follow the Mac's language.
public enum Mana {
    public enum Piece: Equatable, Sendable {
        case text(String)
        case symbol(Symbol)
    }

    public struct Symbol: Equatable, Hashable, Sendable {
        public enum Kind: Equatable, Hashable, Sendable {
            /// W, U, B, R, G or C, drawn as its glyph on its colour.
            case color(String)
            /// A number or letter on a grey circle: 2, X, 10, ½, …
            case generic(String)
            /// Two halves: colours (`"B"`, `"R"`) or a number and a colour (`"2"`, `"W"`).
            case hybrid(String, String)
            /// Phyrexian mana of a colour (C when it names none): the Φ on that colour.
            case phyrexian(String)
            /// T (tap), Q (untap), E (energy), S (snow): a glyph on a grey circle (Q on black).
            case glyph(String)
        }

        /// What was inside the braces, as written ("B/R").
        public let raw: String
        public let kind: Kind

        public init(_ raw: String) {
            self.raw = raw
            let parts = raw.uppercased().split(separator: "/").map(String.init)
            let colors = parts.filter { Mana.colors.contains($0) }
            if parts.contains("P") {
                kind = .phyrexian(colors.first ?? "C")
            } else if parts.count == 2 {
                kind = .hybrid(parts[0], parts[1])
            } else if parts.count == 1, "WUBRGC".contains(parts[0]), parts[0].count == 1 {
                kind = .color(parts[0])
            } else if parts.count == 1, "TQES".contains(parts[0]), parts[0].count == 1 {
                kind = .glyph(parts[0])
            } else {
                kind = .generic(raw)
            }
        }

        /// What VoiceOver says: "black", "2 or white", "Phyrexian green", "tap".
        public func spoken(_ words: Words = .english) -> String {
            switch kind {
            case .color(let c), .glyph(let c): words.names[c] ?? c
            case .generic(let text): words.names[text.uppercased()] ?? text
            case .hybrid(let a, let b): words.either(words.names[a] ?? a, words.names[b] ?? b)
            case .phyrexian(let c): words.phyrexian(words.names[c] ?? c)
            }
        }
    }

    /// The words VoiceOver reads for symbols, in one language.
    public struct Words: Sendable {
        /// By symbol letter: W, U, B, R, G, C, T, Q, E, S.
        public let names: [String: String]
        public let either: @Sendable (String, String) -> String
        public let phyrexian: @Sendable (String) -> String

        public init(names: [String: String], either: @escaping @Sendable (String, String) -> String,
                    phyrexian: @escaping @Sendable (String) -> String) {
            self.names = names
            self.either = either
            self.phyrexian = phyrexian
        }

        public static let english = Words(
            names: ["W": "white", "U": "blue", "B": "black", "R": "red", "G": "green", "C": "colorless",
                    "T": "tap", "Q": "untap", "E": "energy", "S": "snow"],
            either: { "\($0) or \($1)" }, phyrexian: { "Phyrexian \($0)" })
    }

    static let colors: Set<String> = ["W", "U", "B", "R", "G"]

    /// The text split at every `{…}` of 1 to 12 characters; braces around anything else stay text.
    public static func pieces(_ text: String) -> [Piece] {
        var pieces: [Piece] = []
        var plain = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            plain += rest[..<open]
            let after = rest[rest.index(after: open)...]
            if let close = after.firstIndex(of: "}"), case let inside = after[..<close],
               (1...12).contains(inside.count), !inside.contains("{") {
                if !plain.isEmpty { pieces.append(.text(plain)); plain = "" }
                pieces.append(.symbol(Symbol(String(inside))))
                rest = after[after.index(after: close)...]
            } else {
                plain += "{"
                rest = after
            }
        }
        plain += rest
        if !plain.isEmpty { pieces.append(.text(plain)) }
        return pieces
    }

    /// The text as VoiceOver should read it: every symbol by its name ("{T}: Add {G}." → "tap: Add green.").
    /// A cost of only symbols reads as a list ("{2}{B}{G}" → "2, black, green").
    public static func spoken(_ text: String, _ words: Words = .english) -> String {
        let pieces = pieces(text)
        if pieces.allSatisfy({ if case .symbol = $0 { true } else { false } }) {
            return pieces.compactMap { if case .symbol(let s) = $0 { s.spoken(words) } else { nil } }
                .joined(separator: ", ")
        }
        return pieces.map {
            switch $0 {
            case .text(let t): t
            case .symbol(let s): s.spoken(words)
            }
        }.joined()
    }
}
