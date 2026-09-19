import AppKit

// Renders the SF Symbol "figure.walk" as a large white-on-transparent mask PNG.
let size: CGFloat = 1024
let config = NSImage.SymbolConfiguration(pointSize: 640, weight: .regular)
guard let symbol = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
    fatalError("symbol not found")
}

let out = NSImage(size: NSSize(width: size, height: size))
out.lockFocus()
NSColor.clear.set()
NSRect(x: 0, y: 0, width: size, height: size).fill()
NSColor.white.set()
let s = symbol.size
let scale = min((size * 0.66) / s.height, (size * 0.66) / s.width)
let w = s.width * scale, h = s.height * scale
let rect = NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h)
// Draw as a template tinted white
let tinted = symbol.copy() as! NSImage
tinted.isTemplate = true
tinted.lockFocus()
NSColor.white.set()
NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
tinted.unlockFocus()
tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
out.unlockFocus()

guard let tiff = out.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("encode failed")
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1]) symbol size \(s)")
