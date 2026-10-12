// Moldura de janela do macOS para os prints do README: fundo sólido onde a captura ficou
// transparente, cantos arredondados, borda fina e sombra suave.
// xcrun swift Scripts/frame-screenshot.swift <entrada.png> <saida.png>
import AppKit

let input = NSImage(contentsOfFile: CommandLine.arguments[1])!
let source = input.representations.first as! NSBitmapImageRep
let w = CGFloat(source.pixelsWide), h = CGFloat(source.pixelsHigh)
let margin: CGFloat = 80, radius: CGFloat = 24

let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w + margin * 2), pixelsHigh: Int(h + margin * 2),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
let ctx = NSGraphicsContext.current!.cgContext
let frame = CGRect(x: margin, y: margin, width: w, height: h)
let shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.addPath(shape)
ctx.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
source.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
ctx.restoreGState()

ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: 1, dy: 1), cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
ctx.setLineWidth(2)
ctx.strokePath()
NSGraphicsContext.restoreGraphicsState()

try out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
