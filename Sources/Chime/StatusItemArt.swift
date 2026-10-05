import AppKit
import CoreImage

/// What a tracked app's menu bar item shows.
struct StatusItemContent {
    var image: NSImage
    /// Text shown after the image; empty for none.
    var title = ""
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
