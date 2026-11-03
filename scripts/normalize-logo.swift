// fetch-logos.py'nin yardımcısı: indirilen simgeyi 192×192 PNG'ye çevirir.
// Kare ve opak simgeler daireyi doldurur; şeffaf zeminli logolar beyaz zemine (logo açık renkliyse
// kurum rengine) ortalanır.
//
// Kullanım: normalize-logo <girdi> <çıktı.png> <kurum rengi, ör. E30613>
// Çıktı: "<genişlik> <yükseklik>"; görsel okunamazsa 1, tek renkten ibaretse 3 ile çıkar.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 4, let brand = UInt32(arguments[3], radix: 16) else {
    FileHandle.standardError.write("Kullanım: normalize-logo <girdi> <çıktı.png> <renk>\n".data(using: .utf8)!)
    exit(2)
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil) else { exit(1) }
let images = (0..<CGImageSourceGetCount(source)).compactMap { CGImageSourceCreateImageAtIndex(source, $0, nil) }
guard let image = images.max(by: { $0.width * $0.height < $1.width * $1.height }) else { exit(1) }

let width = image.width
let height = image.height
let space = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

// Piksel incelemesi: şeffaflık oranı, opak piksellerin ortalama parlaklığı ve köşe rengi.
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let probe = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: space, bitmapInfo: bitmapInfo) else { exit(1) }
probe.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

var transparent = 0
var luminanceSum = 0.0
var luminanceSquares = 0.0
var opaque = 0
for index in stride(from: 0, to: pixels.count, by: 4) {
    let alpha = Double(pixels[index + 3]) / 255
    if alpha < 0.5 {
        transparent += 1
        continue
    }
    opaque += 1
    let red = Double(pixels[index]) / 255 / alpha
    let green = Double(pixels[index + 1]) / 255 / alpha
    let blue = Double(pixels[index + 2]) / 255 / alpha
    let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
    luminanceSum += luminance
    luminanceSquares += luminance * luminance
}
let transparentRatio = Double(transparent) / Double(width * height)
let averageLuminance = opaque > 0 ? luminanceSum / Double(opaque) : 1
let variance = opaque > 0 ? luminanceSquares / Double(opaque) - averageLuminance * averageLuminance : 0

// Düz renk kare ya da neredeyse boş görsel logo değildir.
if opaque < width * height / 50 || (transparentRatio < 0.03 && variance < 0.002) {
    exit(3)
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let side = 192
guard let output = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                             space: space, bitmapInfo: bitmapInfo) else { exit(1) }
output.interpolationQuality = .high
let canvas = CGRect(x: 0, y: 0, width: side, height: side)
let aspect = Double(width) / Double(height)

if transparentRatio < 0.03 && abs(aspect - 1) < 0.05 {
    // Opak kare simge: daireyi doldursun. (İçeriden çizmek, yeni iOS simgelerinin kenar parıltısını ortaya çıkarıyor.)
    output.draw(image, in: canvas)
} else {
    let background: CGColor
    if transparentRatio < 0.03 {
        // Opak ama kare değil: kendi köşe rengini zemin yap.
        let corner = (height - 1) * width * 4
        background = CGColor(red: CGFloat(pixels[corner]) / 255, green: CGFloat(pixels[corner + 1]) / 255,
                             blue: CGFloat(pixels[corner + 2]) / 255, alpha: 1)
    } else {
        background = averageLuminance > 0.75 ? color(brand) : CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    }
    output.setFillColor(background)
    output.fill(canvas)
    let inset = Double(side) * 0.16
    let box = Double(side) - inset * 2
    let fitted = aspect >= 1 ? CGSize(width: box, height: box / aspect) : CGSize(width: box * aspect, height: box)
    output.draw(image, in: CGRect(x: (Double(side) - fitted.width) / 2, y: (Double(side) - fitted.height) / 2,
                                  width: fitted.width, height: fitted.height))
}

guard let result = output.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("\(width) \(height)")
