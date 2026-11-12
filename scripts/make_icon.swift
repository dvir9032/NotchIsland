// Draws the app icon: a dark rounded square with a black island and glowing equalizer bars.
// Usage: swift scripts/make_icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824pt body, centered, continuous corners.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.addPath(bodyPath)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor(red: 0.27, green: 0.20, blue: 0.62, alpha: 1).cgColor,
    NSColor(red: 0.07, green: 0.06, blue: 0.16, alpha: 1).cgColor,
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// Soft glow under the island.
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor(red: 0.55, green: 0.45, blue: 1, alpha: 0.55).cgColor,
    NSColor(red: 0.55, green: 0.45, blue: 1, alpha: 0).cgColor,
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 600), startRadius: 0, endCenter: CGPoint(x: 512, y: 600), endRadius: 420, options: [])
ctx.restoreGState()

// The island.
let island = CGRect(x: 512 - 300, y: 520, width: 600, height: 170)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.6).cgColor)
ctx.addPath(CGPath(roundedRect: island, cornerWidth: 85, cornerHeight: 85, transform: nil))
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

// Album square on the left.
let art = CGRect(x: island.minX + 48, y: island.midY - 46, width: 92, height: 92)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: art, cornerWidth: 22, cornerHeight: 22, transform: nil))
ctx.clip()
let artGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor(red: 1, green: 0.45, blue: 0.35, alpha: 1).cgColor,
    NSColor(red: 0.95, green: 0.2, blue: 0.55, alpha: 1).cgColor,
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(artGrad, start: CGPoint(x: art.minX, y: art.maxY), end: CGPoint(x: art.maxX, y: art.minY), options: [])
ctx.restoreGState()

// Equalizer bars on the right.
let heights: [CGFloat] = [70, 110, 52, 92]
let barW: CGFloat = 22, gap: CGFloat = 16
var x = island.maxX - 48 - (barW * 4 + gap * 3)
for (i, h) in heights.enumerated() {
    let t = CGFloat(i) / 3
    let color = NSColor(red: 0.55 + 0.4 * t, green: 0.85 - 0.3 * t, blue: 1, alpha: 1)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18, color: color.withAlphaComponent(0.9).cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: island.midY - h / 2, width: barW, height: h), cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
    ctx.setFillColor(color.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    x += barW + gap
}

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
