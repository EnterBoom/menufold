import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let extent = CGFloat(pixels)
        NSColor(calibratedRed: 0.17, green: 0.28, blue: 0.24, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: extent * 0.07, y: extent * 0.07,
            width: extent * 0.86, height: extent * 0.86),
            xRadius: extent * 0.19, yRadius: extent * 0.19).fill()
        NSColor(calibratedWhite: 0.94, alpha: 1).setStroke()
        let path = NSBezierPath()
        path.lineWidth = extent * 0.065
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: extent * 0.42, y: extent * 0.32))
        path.line(to: NSPoint(x: extent * 0.25, y: extent * 0.50))
        path.line(to: NSPoint(x: extent * 0.42, y: extent * 0.68))
        path.move(to: NSPoint(x: extent * 0.61, y: extent * 0.30))
        path.line(to: NSPoint(x: extent * 0.61, y: extent * 0.70))
        path.move(to: NSPoint(x: extent * 0.75, y: extent * 0.30))
        path.line(to: NSPoint(x: extent * 0.75, y: extent * 0.70))
        path.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        let file = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    }
}
