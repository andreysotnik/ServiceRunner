// Renders the app icon: swift scripts/make-icon.swift <output.icns>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024

    // Body per the macOS icon grid: 824pt square, ~185pt corner radius, soft drop shadow.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(red: 0.13, green: 0.16, blue: 0.32, alpha: 1).cgColor,
            NSColor(red: 0.20, green: 0.31, blue: 0.62, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])

    // Three server units with status LEDs: running, running, stopped.
    let unitWidth: CGFloat = 560 * s
    let unitHeight: CGFloat = 150 * s
    let gap: CGFloat = 42 * s
    let stackHeight = unitHeight * 3 + gap * 2
    let x0 = (size - unitWidth) / 2
    let y0 = (size - stackHeight) / 2
    let leds: [NSColor] = [.systemGreen, .systemGreen, NSColor.white.withAlphaComponent(0.25)]
    for (i, led) in leds.enumerated() {
        let y = y0 + CGFloat(2 - i) * (unitHeight + gap)
        let unit = CGRect(x: x0, y: y, width: unitWidth, height: unitHeight)
        ctx.addPath(CGPath(roundedRect: unit, cornerWidth: 34 * s, cornerHeight: 34 * s, transform: nil))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        ctx.fillPath()

        // Vent slots.
        ctx.setFillColor(NSColor(red: 0.13, green: 0.16, blue: 0.32, alpha: 0.35).cgColor)
        for j in 0..<4 {
            let slot = CGRect(x: x0 + 60 * s + CGFloat(j) * 52 * s, y: y + 45 * s, width: 22 * s, height: 60 * s)
            ctx.addPath(CGPath(roundedRect: slot, cornerWidth: 11 * s, cornerHeight: 11 * s, transform: nil))
        }
        ctx.fillPath()

        // LED with glow.
        let ledRect = CGRect(x: x0 + unitWidth - 120 * s, y: y + (unitHeight - 56 * s) / 2, width: 56 * s, height: 56 * s)
        ctx.saveGState()
        if led != leds.last { ctx.setShadow(offset: .zero, blur: 24 * s, color: led.cgColor) }
        ctx.setFillColor(i == 2 ? NSColor(red: 0.13, green: 0.16, blue: 0.32, alpha: 0.25).cgColor : led.cgColor)
        ctx.fillEllipse(in: ledRect)
        ctx.restoreGState()
    }
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(getpid()).iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = renderIcon(size: px).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}

let outURL = URL(fileURLWithPath: output)
try? fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outURL.path]
try! iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Иконка: \(outURL.path)")
