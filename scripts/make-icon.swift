// Draws Chime's app icon and writes it as an .icns file.
//
//     swift scripts/make-icon.swift Resources/AppIcon.icns
//
// The artwork is laid out on a 1024-point canvas with y pointing up, following
// the macOS icon grid: an 824-point rounded square with a soft drop shadow.

import AppKit

let canvas: CGFloat = 1024
let center = canvas / 2

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

/// The macOS icon shape: a superellipse, whose corners curve more smoothly
/// than circular arcs.
func tile() -> CGPath {
    let radius: CGFloat = 412
    let exponent: CGFloat = 5
    let path = CGMutablePath()
    for step in 0..<720 {
        let angle = CGFloat(step) / 720 * 2 * .pi
        let x = pow(abs(cos(angle)), 2 / exponent) * radius * (cos(angle) < 0 ? -1 : 1)
        let y = pow(abs(sin(angle)), 2 / exponent) * radius * (sin(angle) < 0 ? -1 : 1)
        let point = CGPoint(x: center + x, y: center + y)
        if step == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }
    path.closeSubpath()
    return path
}

/// A bell around the origin: crown, body flaring out to a rim, and a clapper.
func bell() -> CGPath {
    // The body, traced from the top down its right side and back up the left.
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 0, y: 232))
    body.addCurve(to: CGPoint(x: 166, y: 62), control1: CGPoint(x: 96, y: 232), control2: CGPoint(x: 166, y: 160))
    body.addCurve(to: CGPoint(x: 218, y: -118), control1: CGPoint(x: 166, y: -24), control2: CGPoint(x: 180, y: -74))
    body.addCurve(to: CGPoint(x: 246, y: -150), control1: CGPoint(x: 232, y: -132), control2: CGPoint(x: 246, y: -138))
    body.addCurve(to: CGPoint(x: 214, y: -182), control1: CGPoint(x: 246, y: -170), control2: CGPoint(x: 232, y: -182))
    body.addLine(to: CGPoint(x: -214, y: -182))
    body.addCurve(to: CGPoint(x: -246, y: -150), control1: CGPoint(x: -232, y: -182), control2: CGPoint(x: -246, y: -170))
    body.addCurve(to: CGPoint(x: -218, y: -118), control1: CGPoint(x: -246, y: -138), control2: CGPoint(x: -232, y: -132))
    body.addCurve(to: CGPoint(x: -166, y: 62), control1: CGPoint(x: -180, y: -74), control2: CGPoint(x: -166, y: -24))
    body.addCurve(to: CGPoint(x: 0, y: 232), control1: CGPoint(x: -166, y: 160), control2: CGPoint(x: -96, y: 232))
    body.closeSubpath()

    // The crown it hangs from, overlapping the top of the body.
    let crown = CGPath(
        roundedRect: CGRect(x: -36, y: 206, width: 72, height: 80),
        cornerWidth: 36,
        cornerHeight: 36,
        transform: nil
    )

    // The clapper: the lower half of a disc, set apart from the rim.
    let clapper = CGMutablePath()
    clapper.move(to: CGPoint(x: -72, y: -222))
    clapper.addArc(center: CGPoint(x: 0, y: -222), radius: 72, startAngle: .pi, endAngle: 0, clockwise: false)
    clapper.closeSubpath()

    return body.union(crown).union(clapper)
}

func drawIcon(in context: CGContext) {
    let tilePath = tile()

    // The tile, with the drop shadow of the macOS icon grid.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.32))
    context.addPath(tilePath)
    context.setFillColor(color(0x4338CA))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0x7C8CFF), color(0x5B4FE9), color(0x3B23B8)]),
        start: CGPoint(x: center, y: 936),
        end: CGPoint(x: center, y: 88),
        options: []
    )
    // A soft glow behind the bell, so the tile is not a flat field.
    context.drawRadialGradient(
        gradient([color(0xFFFFFF, alpha: 0.26), color(0xFFFFFF, alpha: 0)]),
        startCenter: CGPoint(x: 400, y: 700), startRadius: 0,
        endCenter: CGPoint(x: 400, y: 700), endRadius: 520,
        options: []
    )
    context.restoreGState()

    // The bell, tilted as if mid-ring, with the badge on its shoulder.
    let badgeCenter = CGPoint(x: 682, y: 704)
    let badgeRadius: CGFloat = 104
    let badgeGap: CGFloat = 30

    var placement = CGAffineTransform(translationX: center - 18, y: center + 6).rotated(by: 12 * .pi / 180)
    let bellPath = bell().copy(using: &placement)!

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x1E1470, alpha: 0.45))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.addPath(bellPath)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0xFFFFFF), color(0xDCE0FF)]),
        start: CGPoint(x: center, y: 780),
        end: CGPoint(x: center, y: 250),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    // Cut the bell away around the badge so the two never touch.
    context.setBlendMode(.clear)
    context.fillEllipse(in: CGRect(
        x: badgeCenter.x - badgeRadius - badgeGap,
        y: badgeCenter.y - badgeRadius - badgeGap,
        width: (badgeRadius + badgeGap) * 2,
        height: (badgeRadius + badgeGap) * 2
    ))
    context.endTransparencyLayer()
    context.restoreGState()

    let badge = CGRect(
        x: badgeCenter.x - badgeRadius,
        y: badgeCenter.y - badgeRadius,
        width: badgeRadius * 2,
        height: badgeRadius * 2
    )
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0x1E1470, alpha: 0.4))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.addEllipse(in: badge)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0xFF7A6B), color(0xFF3B30)]),
        start: CGPoint(x: badgeCenter.x, y: badge.maxY),
        end: CGPoint(x: badgeCenter.x, y: badge.minY),
        options: []
    )
    context.endTransparencyLayer()
    context.restoreGState()
}

func renderPNG(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(in: context)
    return bitmap.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift make-icon.swift <output.icns>\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

let iconset = FileManager.default.temporaryDirectory.appending(path: "Chime-\(ProcessInfo.processInfo.processIdentifier).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

// Every size an .icns holds, each drawn from the vector artwork at its own resolution.
for points in [16, 32, 128, 256, 512] {
    try renderPNG(pixels: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try renderPNG(pixels: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
