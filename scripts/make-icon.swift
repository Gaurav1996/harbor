import AppKit
import Foundation

// Original geometric artwork; generated locally with system drawing APIs.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    NSColor(calibratedRed: 0.14, green: 0.40, blue: 0.35, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 205, yRadius: 205).fill()
    NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.92, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 222, y: 275, width: 580, height: 474), xRadius: 65, yRadius: 65).fill()
    NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.26, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 262, y: 326, width: 500, height: 100), xRadius: 24, yRadius: 24).fill()
    NSColor(calibratedRed: 0.86, green: 0.92, blue: 0.85, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 685, y: 357, width: 35, height: 35)).fill()
    NSColor(calibratedRed: 0.14, green: 0.40, blue: 0.35, alpha: 1).setStroke()
    let check = NSBezierPath(); check.lineWidth = 43; check.lineCapStyle = .round; check.lineJoinStyle = .round
    check.move(to: NSPoint(x: 386, y: 583)); check.line(to: NSPoint(x: 474, y: 503)); check.line(to: NSPoint(x: 643, y: 666)); check.stroke()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = bitmap.representation(using: .png, properties: [:])!
    let name: String
    switch size {
    case 16: name = "icon_16x16.png"
    case 32: name = "icon_16x16@2x.png"
    case 64: name = "icon_32x32@2x.png"
    case 128: name = "icon_128x128.png"
    case 256: name = "icon_128x128@2x.png"
    case 512: name = "icon_256x256@2x.png"
    default: name = "icon_512x512@2x.png"
    }
    try data.write(to: root.appendingPathComponent(name))
}
for (source, target) in [("icon_16x16@2x.png", "icon_32x32.png"), ("icon_128x128@2x.png", "icon_256x256.png"), ("icon_256x256@2x.png", "icon_512x512.png")] {
    let targetURL = root.appendingPathComponent(target)
    try Data(contentsOf: root.appendingPathComponent(source)).write(to: targetURL)
}
