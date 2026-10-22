import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.08, green: 0.19, blue: 0.23, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210).fill()
let screen = NSBezierPath(roundedRect: NSRect(x: 170, y: 280, width: 684, height: 490), xRadius: 55, yRadius: 55)
NSColor(calibratedWhite: 0.96, alpha: 1).setStroke()
screen.lineWidth = 32
screen.stroke()
let colors: [NSColor] = [
    NSColor(calibratedRed: 0.28, green: 0.83, blue: 0.70, alpha: 1),
    NSColor(calibratedRed: 0.35, green: 0.66, blue: 0.88, alpha: 1),
    NSColor(calibratedRed: 0.26, green: 0.56, blue: 0.63, alpha: 1),
    NSColor(calibratedRed: 0.18, green: 0.39, blue: 0.47, alpha: 1)
]
for row in 0..<2 {
    for column in 0..<3 {
        colors[(row * 3 + column) % colors.count].setFill()
        NSBezierPath(roundedRect: NSRect(x: 218 + column * 202, y: 330 + row * 200, width: 184, height: 180), xRadius: 12, yRadius: 12).fill()
    }
}
NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 489, y: 200, width: 46, height: 65), xRadius: 12, yRadius: 12).fill()
NSBezierPath(roundedRect: NSRect(x: 370, y: 178, width: 284, height: 32), xRadius: 16, yRadius: 16).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
