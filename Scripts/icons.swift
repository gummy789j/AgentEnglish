// Run with: swift Scripts/icons.swift <mark.svg> <iconset-dir> <preview.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 4 else { fatalError("Expected the SVG, iconset folder and preview path.") }
let svg = try String(contentsOfFile: args[1], encoding: .utf8)
let mark = NSImage(data: Data(svg.replacingOccurrences(of: "#000000", with: "#9DF1CC").utf8))!
func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels)/128, y: CGFloat(pixels)/128)
    let tile = NSBezierPath(roundedRect: NSRect(x: 6, y: 6, width: 116, height: 116), xRadius: 27, yRadius: 27)
    NSGradient(starting: NSColor(srgbRed:0.12, green:0.26, blue:0.26, alpha:1),
               ending: NSColor(srgbRed:0.06, green:0.09, blue:0.13, alpha:1))!.draw(in:tile, angle:-50)
    NSColor(white:1, alpha:0.18).setStroke()
    tile.lineWidth = 1; tile.stroke()
    mark.draw(in: NSRect(x:29, y:28, width:73, height:73))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using:.png, properties:[:])!
}
let dir = URL(fileURLWithPath:args[2])
try FileManager.default.createDirectory(at:dir, withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(size*scale).write(to:dir.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
try render(256).write(to:URL(fileURLWithPath:args[3]))
