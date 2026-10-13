import AppKit

/// Draws the colored images shown in the menu bar.
enum StatusGlyph {
    private static let height: CGFloat = 14

    static func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "GitHub Actions") ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// A horizontal bar filled to `fraction` of its width.
    static func progress(_ fraction: Double, color: NSColor) -> NSImage {
        draw(width: 30) { rect in
            let track = NSRect(x: 0, y: (rect.height - 8) / 2, width: rect.width, height: 8)
            NSColor.gray.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()

            let clamped = min(max(fraction, 0), 1)
            guard clamped > 0 else { return }
            var filled = track
            filled.size.width = max(track.height, track.width * clamped)
            color.setFill()
            NSBezierPath(roundedRect: filled, xRadius: 4, yRadius: 4).fill()
        }
    }

    private static func draw(width: CGFloat, _ body: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            body(rect)
            return true
        }
        image.isTemplate = false
        return image
    }
}
