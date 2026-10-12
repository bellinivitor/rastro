// Gera o AppIcon.iconset do Rastro: xcrun swift Scripts/make-icon.swift <saida.iconset>
// Uma trilha que vem desbotada e passa por três pontos que crescem até o mais recente.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
}

func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect {
    CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let s = CGFloat(pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let space = CGColorSpaceCreateDeviceRGB()

    // Grade de ícones do macOS: conteúdo em ~80% do quadro.
    let inset = s * 0.098
    let rect = CGRect(x: inset, y: inset * 1.15, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Sombra
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.025, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0.1, 0.1, 0.11))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Fundo grafite, um pouco mais claro em cima.
    let background = CGGradient(colorsSpace: space, colors: [rgb(0.19, 0.20, 0.22), rgb(0.09, 0.09, 0.10)] as CFArray,
                                locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])

    // A trilha: desbota para a esquerda (o passado).
    let y = rect.midY
    ctx.saveGState()
    let line = CGRect(x: rect.minX + rect.width * 0.10, y: y - s * 0.016, width: rect.width * 0.68, height: s * 0.032)
    ctx.addPath(CGPath(roundedRect: line, cornerWidth: s * 0.016, cornerHeight: s * 0.016, transform: nil))
    ctx.clip()
    let fade = CGGradient(colorsSpace: space, colors: [rgb(1, 1, 1, 0), rgb(1, 1, 1, 0.9)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(fade, start: CGPoint(x: line.minX, y: y), end: CGPoint(x: line.maxX, y: y), options: [])
    ctx.restoreGState()

    // Três pontos que crescem até o mais recente, em branco com degradê discreto.
    for (x, r) in [(CGFloat(0.32), CGFloat(0.034)), (0.54, 0.046), (0.78, 0.066)] {
        ctx.addEllipse(in: circle(CGPoint(x: rect.minX + rect.width * x, y: y), s * r))
    }
    ctx.saveGState()
    ctx.clip()
    let ink = CGGradient(colorsSpace: space, colors: [rgb(1, 1, 1), rgb(0.78, 0.80, 0.84)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(ink, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()
    ctx.restoreGState()

    // Borda interna fina: deixa o recorte nítido no Dock escuro.
    let edge = rect.insetBy(dx: s * 0.003, dy: s * 0.003)
    ctx.addPath(CGPath(roundedRect: edge, cornerWidth: radius * 0.99, cornerHeight: radius * 0.99, transform: nil))
    ctx.setStrokeColor(rgb(1, 1, 1, 0.10))
    ctx.setLineWidth(max(1, s * 0.004))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(pixels: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(pixels: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("ok")
