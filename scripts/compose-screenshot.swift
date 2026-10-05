// Places a demo snapshot (transparent background) on a desktop-style backdrop
// with a soft shadow. Usage: swift scripts/compose-screenshot.swift snapshot.png out.png
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let data = FileManager.default.contents(atPath: args[1]),
      let panel = NSBitmapImageRep(data: data)?.cgImage else {
    fatalError("usage: compose-screenshot.swift panel.png out.png")
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let pw = CGFloat(panel.width), ph = CGFloat(panel.height)
let pad = (max(pw, ph) * 0.09).rounded()
let size = CGSize(width: pw + 2 * pad, height: ph + 2 * pad)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!

// Backdrop: a deep diagonal gradient with two soft glows, like a macOS wallpaper.
let base = CGGradient(colorsSpace: space, colors: [color(0x141B3D), color(0x2B1F5C), color(0x4A2466)] as CFArray,
                      locations: [0, 0.55, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
for (x, y, r, hex, a) in [(0.18, 0.85, 0.55, 0x3D6BFF, 0.55), (0.85, 0.15, 0.6, 0xFF4F8B, 0.35)] as [(CGFloat, CGFloat, CGFloat, UInt32, CGFloat)] {
    let glow = CGGradient(colorsSpace: space, colors: [color(hex, a), color(hex, 0)] as CFArray, locations: [0, 1])!
    let center = CGPoint(x: size.width * x, y: size.height * y)
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center,
                           endRadius: max(size.width, size.height) * r, options: [])
}

// The panel with a soft shadow.
let rect = CGRect(x: pad, y: pad, width: pw, height: ph)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -pad * 0.18), blur: pad * 0.55, color: color(0x000000, 0.55))
ctx.draw(panel, in: rect)
ctx.restoreGState()

// Keep README images reasonably small: at most 2000px wide.
var image = ctx.makeImage()!
if size.width > 2000 {
    let scale = 2000 / size.width
    let out = CGSize(width: 2000, height: (size.height * scale).rounded())
    let small = CGContext(data: nil, width: Int(out.width), height: Int(out.height), bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    small.interpolationQuality = .high
    small.draw(image, in: CGRect(origin: .zero, size: out))
    image = small.makeImage()!
}
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("Wrote \(args[2]) (\(image.width)×\(image.height))")
