// Uygulama simgesini çizer. Kullanım:
//   swift scripts/app-icon.swift <çıktı.png> [standard|dark|tinted]
// dark: koyu zeminli sürüm (iPhone koyu moddayken); tinted: renklendirilmiş ana ekran için gri tonlu sürüm.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "standard"
let isDark = mode == "dark" || mode == "tinted"
let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func gradient(_ colors: [UInt32], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors.map { rgb($0) } as CFArray, locations: locations)!
}
func fill(_ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
func polygon(_ points: [CGPoint]) -> CGPath {
    let p = CGMutablePath(); p.addLines(between: points); p.closeSubpath(); return p
}
func text(_ string: String, size fontSize: CGFloat, color: CGColor, center: CGPoint) {
    let font = CTFontCreateWithName("Georgia-Bold" as CFString, fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: center.x - b.midX, y: center.y - b.midY)
    CTLineDraw(line, ctx)
}

// Arka plan: koyu zümrüt, ortada hafif aydınlık. Koyu sürümde neredeyse siyah.
ctx.drawRadialGradient(gradient(isDark ? [0x1C2621, 0x0C110E, 0x070908] : [0x23875A, 0x0B3A26, 0x072619], [0, 0.65, 1]),
    startCenter: CGPoint(x: 512, y: 600), startRadius: 0, endCenter: CGPoint(x: 512, y: 600), endRadius: 760, options: [.drawsAfterEndLocation])
// Arkada altın parıltı
ctx.drawRadialGradient(CGGradient(colorsSpace: space, colors: [rgb(0xF4D98A, isDark ? 0.22 : 0.38), rgb(0xF4D98A, 0)] as CFArray, locations: [0, 1])!,
    startCenter: CGPoint(x: 540, y: 600), startRadius: 0, endCenter: CGPoint(x: 540, y: 600), endRadius: 420, options: [])

let gold = gradient([0xFFF1B8, 0xF2C94C, 0xC8921F, 0xF7DA7A, 0xA9741A], [0, 0.3, 0.55, 0.78, 1])
let goldDark = gradient([0xE5B43C, 0x9C6A12])

func coin(center: CGPoint, radius: CGFloat, letter: String) {
    let outer = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 40, color: rgb(0x000000, 0.45))
    ctx.addPath(outer); ctx.setFillColor(rgb(0xC8921F)); ctx.fillPath()
    ctx.restoreGState()
    fill(outer, gold, from: CGPoint(x: center.x - radius, y: center.y + radius), to: CGPoint(x: center.x + radius, y: center.y - radius))
    // Kenar halkası
    ctx.setStrokeColor(rgb(0x9C6A12, 0.9)); ctx.setLineWidth(radius * 0.05)
    ctx.addEllipse(in: CGRect(x: center.x - radius * 0.82, y: center.y - radius * 0.82, width: radius * 1.64, height: radius * 1.64)); ctx.strokePath()
    ctx.setStrokeColor(rgb(0xFFF1B8, 0.7)); ctx.setLineWidth(radius * 0.02)
    ctx.addEllipse(in: CGRect(x: center.x - radius * 0.77, y: center.y - radius * 0.77, width: radius * 1.54, height: radius * 1.54)); ctx.strokePath()
    // Kabartma harf
    text(letter, size: radius * 1.05, color: rgb(0xFFF6D0, 0.8), center: CGPoint(x: center.x - 4, y: center.y + 4))
    text(letter, size: radius * 1.05, color: rgb(0x8A5A0C), center: center)
}

// Arka sikke ve ön sikke
coin(center: CGPoint(x: 390, y: 600), radius: 165, letter: "₺")
coin(center: CGPoint(x: 600, y: 660), radius: 215, letter: "₺")

// Külçe
let baseY: CGFloat = 215, frontTop: CGFloat = 385, topY: CGFloat = 470
let front = polygon([CGPoint(x: 205, y: baseY), CGPoint(x: 819, y: baseY), CGPoint(x: 752, y: frontTop), CGPoint(x: 272, y: frontTop)])
let top = polygon([CGPoint(x: 272, y: frontTop), CGPoint(x: 752, y: frontTop), CGPoint(x: 690, y: topY), CGPoint(x: 334, y: topY)])
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 50, color: rgb(0x000000, 0.5))
ctx.addPath(front); ctx.addPath(top); ctx.setFillColor(rgb(0xB07F1A)); ctx.fillPath()
ctx.restoreGState()
fill(front, gradient([0x8F5F10, 0xD9A532, 0xF5D26E, 0xC08A22]), from: CGPoint(x: 0, y: baseY), to: CGPoint(x: 0, y: frontTop))
fill(top, gradient([0xF2C94C, 0xFFF1B8]), from: CGPoint(x: 0, y: frontTop), to: CGPoint(x: 0, y: topY))
// Ön yüzde ince parlama ve kazıma çizgisi
ctx.setStrokeColor(rgb(0xFFF6D0, 0.75)); ctx.setLineWidth(5)
ctx.move(to: CGPoint(x: 272, y: frontTop)); ctx.addLine(to: CGPoint(x: 752, y: frontTop)); ctx.strokePath()
let plate = CGPath(roundedRect: CGRect(x: 392, y: 255, width: 240, height: 90), cornerWidth: 14, cornerHeight: 14, transform: nil)
ctx.addPath(plate); ctx.setStrokeColor(rgb(0x7A4E0A, 0.55)); ctx.setLineWidth(6); ctx.strokePath()
text("999.9", size: 58, color: rgb(0x7A4E0A, 0.75), center: CGPoint(x: 512, y: 300))

var image = ctx.makeImage()!
if mode == "tinted" {
    // Sistem renklendirmeyi parlaklığa göre yapar: önce gri tona, sonra yeniden RGB'ye.
    let gray = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    gray.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let rgbContext = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                               space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    rgbContext.draw(gray.makeImage()!, in: CGRect(x: 0, y: 0, width: size, height: size))
    image = rgbContext.makeImage()!
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
