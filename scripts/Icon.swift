import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func lengthBytes(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
let types = [16: ["icp4", "ic11"], 32: ["icp5", "ic12"],
    128: ["ic07", "ic13"], 256: ["ic08", "ic14"], 512: ["ic09", "ic10"]]
var chunks = Data()
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
            pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.13, green: 0.52, blue: 0.43, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.05, y: p * 0.05, width: p * 0.9,
            height: p * 0.9), xRadius: p * 0.22, yRadius: p * 0.22).fill()
        if let symbol = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: p * 0.56, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            symbol.withSymbolConfiguration(config)?.draw(in: NSRect(x: p * 0.23,
                y: p * 0.2, width: p * 0.54, height: p * 0.6))
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: url)
        chunks.append(Data(types[size]![scale - 1].utf8))
        chunks.append(lengthBytes(png.count + 8))
        chunks.append(png)
    }
}
var icon = Data("icns".utf8)
icon.append(lengthBytes(chunks.count + 8))
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
