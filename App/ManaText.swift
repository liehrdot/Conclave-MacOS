import AppKit
import AVFoundation
import ConclaveEngine
import SwiftUI

/// Text with its mana symbols drawn like on the cards: "{2}{B}{G}" shows a grey 2, a black and a green symbol inside
/// the line, at the text's size. VoiceOver reads the symbols by name in the Mac's language. The AppKit twin of the
/// iPhone app's `ManaText`.
struct ManaText: View {
    let text: String
    let style: Font.TextStyle
    @ScaledMetric private var size: CGFloat

    init(_ text: String, style: Font.TextStyle = .body) {
        self.text = text
        self.style = style
        _size = ScaledMetric(wrappedValue: Self.baseSize(style), relativeTo: style)
    }

    var body: some View {
        line
            .font(.system(style))
            .accessibilityLabel(Mana.spoken(text, .app))
    }

    private var line: Text {
        var out = Text(verbatim: "")
        var lastWasSymbol = false
        for piece in Mana.pieces(text) {
            switch piece {
            case .text(let plain):
                out = Text("\(out)\(Text(verbatim: plain))")
                lastWasSymbol = false
            case .symbol(let symbol):
                // a hair space between symbols in a row, like the printed costs
                let gap = lastWasSymbol ? Text(verbatim: "\u{200A}") : Text(verbatim: "")
                let image = Text(Image(nsImage: ManaGlyphs.image(symbol, size: size)).renderingMode(.original))
                    .baselineOffset(-size * 0.16)
                out = Text("\(out)\(gap)\(image)")
                lastWasSymbol = true
            }
        }
        return out
    }

    /// About the text style's cap-to-descender height on the Mac, so a symbol sits in the line like a capital.
    private static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 28
        case .title: 24
        case .title2: 19
        case .title3: 17
        case .headline, .body: 14
        case .callout: 13
        case .subheadline: 12
        case .footnote: 11
        default: 10
        }
    }
}

extension Mana.Words {
    /// The symbols' names in the Mac's language.
    static var app: Mana.Words {
        Mana.Words(
            names: ["W": String(localized: "white"), "U": String(localized: "blue"), "B": String(localized: "black"),
                    "R": String(localized: "red"), "G": String(localized: "green"),
                    "C": String(localized: "colorless"), "T": String(localized: "tap"),
                    "Q": String(localized: "untap"), "E": String(localized: "energy"), "S": String(localized: "snow")],
            either: { String(localized: "\($0) or \($1)") },
            phyrexian: { String(localized: "Phyrexian \($0)") })
    }
}

/// The symbols as small pictures: a coloured circle with the symbol's glyph from the Mana font (OFL,
/// App/Resources/Mana-LICENSE.txt), a number for generic mana, split circles for hybrid mana. Drawn once per
/// symbol and size; Magic's own colours in light and dark mode, like the card art.
@MainActor
enum ManaGlyphs {
    private static var drawn: [String: NSImage] = [:]

    /// The circles' colours, the same as the web app's `--ms-*` and the iPhone app's.
    static let fills: [String: NSColor] = [
        "W": NSColor(srgbRed: 1.00, green: 0.98, blue: 0.84, alpha: 1),
        "U": NSColor(srgbRed: 0.67, green: 0.88, blue: 0.98, alpha: 1),
        "B": NSColor(srgbRed: 0.80, green: 0.76, blue: 0.75, alpha: 1),
        "R": NSColor(srgbRed: 0.98, green: 0.67, blue: 0.56, alpha: 1),
        "G": NSColor(srgbRed: 0.61, green: 0.83, blue: 0.68, alpha: 1),
    ]
    static let grey = NSColor(srgbRed: 0.80, green: 0.76, blue: 0.75, alpha: 1)

    static func image(_ symbol: Mana.Symbol, size: CGFloat) -> NSImage {
        let key = "\(symbol.raw.uppercased())@\(Int(size * 4))"
        if let image = drawn[key] { return image }
        let image = NSImage(size: NSSize(width: size, height: size))
        if let rep = render(symbol, size: size, scale: 2) { image.addRepresentation(rep) }
        image.accessibilityDescription = symbol.spoken(.app)
        drawn[key] = image
        return image
    }

    /// Draws into a bitmap right away (at twice the size, for Retina screens), so nothing is drawn later off the
    /// main actor. The context is flipped: y grows downwards, as in the iPhone app's drawing.
    private static func render(_ symbol: Mana.Symbol, size: CGFloat, scale: CGFloat) -> NSBitmapImageRep? {
        let pixels = Int((size * scale).rounded(.up))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bitmap = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = NSSize(width: size, height: size)
        let cg = bitmap.cgContext
        cg.scaleBy(x: CGFloat(pixels) / size, y: CGFloat(pixels) / size)
        cg.translateBy(x: 0, y: size)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        draw(symbol, in: CGRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func draw(_ symbol: Mana.Symbol, in rect: CGRect) {
        let size = rect.width
        func circle(_ color: NSColor) {
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
        switch symbol.kind {
        case .color(let c):
            circle(fills[c] ?? grey)
            glyph(c, in: rect.insetBy(dx: size * 0.13, dy: size * 0.13))
        case .glyph(let g):
            circle(g == "Q" ? .black : grey)
            glyph(g, in: rect.insetBy(dx: size * 0.1, dy: size * 0.1), color: g == "Q" ? .white : .black)
        case .phyrexian(let c):
            circle(fills[c] ?? grey)
            glyph("P", in: rect.insetBy(dx: size * 0.13, dy: size * 0.13))
        case .generic(let text):
            circle(grey)
            number(text, in: rect.insetBy(dx: size * 0.1, dy: size * 0.1), size: size * 0.72)
        case .hybrid(let a, let b):
            // split along the falling diagonal: the first half top left, the second bottom right
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: rect).addClip()
            (fills[a] ?? grey).setFill()
            rect.fill()
            let lower = NSBezierPath()
            lower.move(to: CGPoint(x: size, y: 0))
            lower.line(to: CGPoint(x: size, y: size))
            lower.line(to: CGPoint(x: 0, y: size))
            lower.close()
            (fills[b] ?? grey).setFill()
            lower.fill()
            NSGraphicsContext.restoreGraphicsState()
            let side = size * 0.46
            half(a, in: CGRect(x: size * 0.08, y: size * 0.08, width: side, height: side))
            half(b, in: CGRect(x: size * 0.46, y: size * 0.46, width: side, height: side))
        }
    }

    /// One half of a hybrid symbol: a colour's glyph or a number.
    private static func half(_ part: String, in rect: CGRect) {
        if part.count == 1, "WUBRGC".contains(part) { glyph(part, in: rect) } else { number(part, in: rect, size: rect.height) }
    }

    /// The glyph from the asset catalog, tinted: the template image in its own layer, then the colour drawn over
    /// only its own pixels (`sourceAtop`), so the circle below keeps its colour.
    private static func glyph(_ name: String, in rect: CGRect, color: NSColor = .black) {
        guard let image = NSImage(named: "mana-\(name)"), let cg = NSGraphicsContext.current?.cgContext else { return }
        let fit = AVMakeRect(aspectRatio: image.size, insideRect: rect)
        cg.beginTransparencyLayer(in: fit, auxiliaryInfo: nil)
        image.draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        color.set()
        fit.fill(using: .sourceAtop)
        cg.endTransparencyLayer()
    }

    private static func number(_ text: String, in rect: CGRect, size: CGFloat) {
        var font = NSFont.systemFont(ofSize: size, weight: .semibold)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        var measured = (text as NSString).size(withAttributes: attributes)
        if measured.width > rect.width {  // "10", "CHAOS": smaller until it fits
            font = NSFont.systemFont(ofSize: size * rect.width / measured.width, weight: .semibold)
            attributes[.font] = font
            measured = (text as NSString).size(withAttributes: attributes)
        }
        let origin = CGPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
