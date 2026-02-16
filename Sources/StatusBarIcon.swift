import AppKit

enum StatusBarIcon {
    static func spark(for percentage: Double) -> NSImage {
        let color: NSColor
        if percentage < 70 {
            color = .systemGreen
        } else if percentage < 90 {
            color = .systemOrange
        } else {
            color = .systemRed
        }

        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 8, y: 15))
            path.line(to: NSPoint(x: 9, y: 10))
            path.line(to: NSPoint(x: 13, y: 13))
            path.line(to: NSPoint(x: 10, y: 9))
            path.line(to: NSPoint(x: 15, y: 8))
            path.line(to: NSPoint(x: 10, y: 7))
            path.line(to: NSPoint(x: 13, y: 3))
            path.line(to: NSPoint(x: 9, y: 6))
            path.line(to: NSPoint(x: 8, y: 1))
            path.line(to: NSPoint(x: 7, y: 6))
            path.line(to: NSPoint(x: 3, y: 3))
            path.line(to: NSPoint(x: 6, y: 7))
            path.line(to: NSPoint(x: 1, y: 8))
            path.line(to: NSPoint(x: 6, y: 9))
            path.line(to: NSPoint(x: 3, y: 13))
            path.line(to: NSPoint(x: 7, y: 10))
            path.close()
            color.setFill()
            path.fill()
            return true
        }
        img.isTemplate = false
        return img
    }
}
