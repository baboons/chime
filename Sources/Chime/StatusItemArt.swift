import AppKit
import CoreImage

/// What a tracked app's menu bar item shows.
struct StatusItemContent {
    var image: NSImage
    /// Text shown after the image; empty for none.
    var title = ""
}

/// What an app has to say for itself: the title of its own menu bar item, or
/// what it sent Chime.
struct ItemLabel: Equatable {
    var title: String
    /// The color of the box the title goes in; nil for plain text.
    var color: NSColor?
    /// A mark to go before the title: the name of an SF Symbol, or an image as a `data:` URL.
    var icon: String?
}

/// Draws an app icon with its notification badge for the menu bar.
@MainActor
enum StatusItemArt {
    static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    private static let canvasHeight: CGFloat = 22
    private static let iconSize: CGFloat = 20
    /// The transparent gap that separates a badge from the icon under it.
    private static let badgeGap: CGFloat = 1.5

    private static let pillHeight: CGFloat = 12
    private static let pillPadding: CGFloat = 3.5
    /// How far the pill reaches in over the icon's trailing edge.
    private static let pillOverlap: CGFloat = 9
    private static let pillFont = NSFont.systemFont(ofSize: 9, weight: .bold)

    private static let dotSize: CGFloat = 7

    private static let boxHeight: CGFloat = 20
    private static let boxPadding: CGFloat = 8
    /// The gap between an icon and what follows it.
    private static let boxGap: CGFloat = 5
    private static let boxFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    /// The longest label shown whole. A longer one loses its middle, which says the least.
    private static let labelLimit = 48

    /// How tall the mark before a title is, when it is an image.
    private static let markHeight: CGFloat = 14
    /// The gap between a mark and the title after it.
    private static let markGap: CGFloat = 4
    /// The marks apps sent, as drawn, by what they sent. Nil for one that is not an image.
    private static var marks: [String: NSImage?] = [:]

    /// The app with its badge, followed by what it has to say, if anything.
    static func content(icon: NSImage, badge: Badge?, style: BadgeStyle, label: ItemLabel?) -> StatusItemContent {
        var content = content(icon: icon, badge: badge, style: style)
        guard let label else { return content }

        var title = label.title
        if title.count > labelLimit {
            title = "\(title.prefix(labelLimit / 2))…\(title.suffix(labelLimit / 2 - 1))"
        }
        if !content.title.isEmpty {
            title = "\(content.title) · \(title)"
        }
        let mark = label.icon.flatMap(mark)
        if let color = label.color {
            return StatusItemContent(image: box(title, mark: mark, color: color, after: content.image))
        }
        if let mark {
            content.image = row(content.image, tinted(mark, .controlTextColor))
        }
        content.title = title
        return content
    }

    static func content(icon: NSImage, badge: Badge?, style: BadgeStyle) -> StatusItemContent {
        guard let badge else {
            return StatusItemContent(image: draw(icon, width: iconSize))
        }
        switch style {
        case .number:
            return StatusItemContent(image: draw(icon, width: iconSize), title: badge.short)
        case .pill:
            return StatusItemContent(image: pill(badge.short, over: icon))
        case .dot:
            let dot = NSRect(x: iconSize - dotSize + 1, y: canvasHeight - dotSize - 1, width: dotSize, height: dotSize)
            return StatusItemContent(image: draw(icon, width: dot.maxX) { drawBadge(in: dot) })
        }
    }

    /// A grayscale copy of an app icon, for a menu bar without color.
    static func monochrome(_ icon: NSImage) -> NSImage {
        // Render at 3x so the copy stays sharp on any display.
        var rect = NSRect(x: 0, y: 0, width: iconSize * 3, height: iconSize * 3)
        guard let source = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return icon
        }
        let gray = CIImage(cgImage: source).applyingFilter("CIPhotoEffectMono")
        let result = NSImage(size: NSSize(width: iconSize, height: iconSize))
        result.addRepresentation(NSCIImageRep(ciImage: gray))
        return result
    }

    private static func pill(_ label: String, over icon: NSImage) -> NSImage {
        let text = NSAttributedString(string: label, attributes: [.font: pillFont, .foregroundColor: NSColor.white])
        let textWidth = ceil(text.size().width)
        let width = max(pillHeight, textWidth + pillPadding * 2)
        let pill = NSRect(x: iconSize - pillOverlap, y: canvasHeight - pillHeight, width: width, height: pillHeight)

        return draw(icon, width: max(iconSize, pill.maxX)) {
            drawBadge(in: pill)
            // Center on the digits' cap height; they have no descenders to balance.
            let baseline = pill.midY - pillFont.capHeight / 2
            text.draw(at: NSPoint(x: pill.midX - textWidth / 2, y: baseline + pillFont.descender))
        }
    }

    /// `image` followed by `mark` and `title` in a rounded box of `color`.
    private static func box(_ title: String, mark: NSImage?, color: NSColor, after image: NSImage) -> NSImage {
        // Whichever of black and white reads better on the color.
        let brightness = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
        let ink = brightness > 0.6 ? NSColor.black : NSColor.white
        let text = NSAttributedString(string: title, attributes: [.font: boxFont, .foregroundColor: ink])
        let mark = mark.map { tinted($0, ink) }
        let markWidth = mark.map { $0.size.width + markGap } ?? 0
        let box = NSRect(
            x: image.size.width + boxGap,
            y: (canvasHeight - boxHeight) / 2,
            width: boxPadding * 2 + markWidth + ceil(text.size().width),
            height: boxHeight
        )

        return NSImage(size: NSSize(width: box.maxX, height: canvasHeight), flipped: false) { _ in
            image.draw(in: NSRect(origin: .zero, size: image.size))
            color.setFill()
            NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
            if let mark {
                let origin = NSPoint(x: box.minX + boxPadding, y: (box.midY - mark.size.height / 2).rounded())
                mark.draw(in: NSRect(origin: origin, size: mark.size))
            }
            // Center on the cap height, as the badge does.
            let baseline = box.midY - boxFont.capHeight / 2
            text.draw(at: NSPoint(x: box.minX + boxPadding + markWidth, y: baseline + boxFont.descender))
            return true
        }
    }

    /// The mark an app sent, at the size it is drawn. Nil if `source` is neither
    /// the name of an SF Symbol nor an image as a `data:` URL.
    private static func mark(_ source: String) -> NSImage? {
        if let known = marks[source] {
            return known
        }
        var mark: NSImage?
        if source.hasPrefix("data:") {
            if let comma = source.firstIndex(of: ","), source[..<comma].hasSuffix(";base64"),
               let data = Data(base64Encoded: String(source[source.index(after: comma)...])),
               let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 {
                let width = min(image.size.width * markHeight / image.size.height, markHeight * 2)
                image.size = NSSize(width: ceil(width), height: markHeight)
                mark = image
            }
        } else {
            let size = NSImage.SymbolConfiguration(pointSize: boxFont.pointSize, weight: .medium)
            mark = NSImage(systemSymbolName: source, accessibilityDescription: nil)?.withSymbolConfiguration(size)
        }
        // An app may send a new image with every item, so do not keep them all.
        if marks.count >= 16 {
            marks.removeAll()
        }
        marks[source] = mark
        return mark
    }

    /// `image` followed by `mark`.
    private static func row(_ image: NSImage, _ mark: NSImage) -> NSImage {
        let origin = NSPoint(x: image.size.width + boxGap, y: ((canvasHeight - mark.size.height) / 2).rounded())
        return NSImage(size: NSSize(width: origin.x + mark.size.width, height: canvasHeight), flipped: false) { _ in
            image.draw(in: NSRect(origin: .zero, size: image.size))
            mark.draw(in: NSRect(origin: origin, size: mark.size))
            return true
        }
    }

    /// The shape of `image` in `color`.
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // In a layer of its own, so that the color lands on the shape and not on what is under it.
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            context.endTransparencyLayer()
            return true
        }
    }

    private static func draw(_ icon: NSImage, width: CGFloat, overlay: @escaping () -> Void = {}) -> NSImage {
        NSImage(size: NSSize(width: width, height: canvasHeight), flipped: false) { _ in
            let iconRect = NSRect(x: 0, y: (canvasHeight - iconSize) / 2, width: iconSize, height: iconSize)
            icon.draw(in: iconRect)
            overlay()
            return true
        }
    }

    /// Fills a red capsule, first clearing a gap around it so it reads on any icon.
    private static func drawBadge(in rect: NSRect) {
        let gap = rect.insetBy(dx: -badgeGap, dy: -badgeGap)
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(roundedRect: gap, xRadius: gap.height / 2, yRadius: gap.height / 2).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }
}
