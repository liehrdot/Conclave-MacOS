import Foundation

/// A mana cost split into its symbols: "{2}{B}{G}" › ["2", "B", "G"], "{W/U}" › ["W/U"]. Text outside braces
/// (" // " between two faces) is dropped.
public enum ManaCost {
    public static func symbols(_ cost: String) -> [String] {
        var out: [String] = []
        var current: String?
        for char in cost {
            switch char {
            case "{": current = ""
            case "}":
                if let symbol = current, !symbol.isEmpty { out.append(symbol.uppercased()) }
                current = nil
            default: current?.append(char)
            }
        }
        return out
    }

    /// The colour a symbol is drawn in: "W", "U", "B", "R", "G", or nil for colourless and generic mana.
    /// A hybrid symbol takes its first colour.
    public static func color(of symbol: String) -> String? {
        symbol.split(separator: "/").map(String.init).first { ["W", "U", "B", "R", "G"].contains($0) }
    }
}
