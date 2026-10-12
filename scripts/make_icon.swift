// Renders the app icon to a 1024px PNG: make_icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824px rounded square centred in 1024, with a soft drop shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
NSColor.black.setFill(); shape.fill()
ctx.restoreGState()

ctx.saveGState()
shape.addClip()
NSGradient(colors: [NSColor(red: 0.13, green: 0.80, blue: 0.47, alpha: 1),
                    NSColor(red: 0.04, green: 0.50, blue: 0.47, alpha: 1)])!
    .draw(in: tile, angle: -90)

// Treadmill belt: a dark rounded bar with a lighter top edge and two rollers.
let belt = CGRect(x: 200, y: 250, width: 624, height: 70)
NSColor(white: 0.08, alpha: 0.85).setFill()
NSBezierPath(roundedRect: belt, xRadius: 35, yRadius: 35).fill()
NSColor(white: 1, alpha: 0.35).setFill()
NSBezierPath(roundedRect: CGRect(x: 235, y: 302, width: 554, height: 10), xRadius: 5, yRadius: 5).fill()
for x in [235.0, 789.0] {
    NSColor(white: 1, alpha: 0.5).setFill()
    NSBezierPath(ovalIn: CGRect(x: x - 18, y: 267, width: 36, height: 36)).fill()
}

// Walking figure standing on the belt.
let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
let figure = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: nil)!
    .withSymbolConfiguration(config)!
let fs = figure.size
figure.draw(in: CGRect(x: (size - fs.width) / 2, y: 268, width: fs.width, height: fs.height))
ctx.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
