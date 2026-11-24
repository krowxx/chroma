import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ rgb: Int, opacity: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255, alpha: opacity)
}

func tile(_ rect: CGRect, radius: CGFloat, top: Int, bottom: Int, stroke: CGFloat, shadow: CGFloat) {
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -15), blur: shadow, color: color(0x080913, opacity: 0.7))
    context.addPath(shape)
    context.setFillColor(color(bottom))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [color(top), color(bottom)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    context.restoreGState()
    context.addPath(shape)
    context.setStrokeColor(color(0xFFFFFF, opacity: stroke))
    context.setLineWidth(4)
    context.strokePath()
}

tile(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 191,
     top: 0x303248, bottom: 0x11121E, stroke: 0.17, shadow: 37)
tile(CGRect(x: 319, y: 383, width: 437, height: 368), radius: 88,
     top: 0x59E4B7, bottom: 0x248C80, stroke: 0.33, shadow: 27)
tile(CGRect(x: 295, y: 321, width: 437, height: 368), radius: 88,
     top: 0xFFC58C, bottom: 0xD96368, stroke: 0.31, shadow: 22)
tile(CGRect(x: 269, y: 255, width: 437, height: 368), radius: 88,
     top: 0xBAADFF, bottom: 0x665DE9, stroke: 0.42, shadow: 20)

let image = context.makeImage()!

func png(size: Int) -> Data {
    let canvas = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                           bytesPerRow: size * 4, space: colorSpace,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    canvas.interpolationQuality = .high
    canvas.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, canvas.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}

func chunk(_ type: String, containing payload: Data) -> Data {
    var result = Data(type.utf8)
    var length = UInt32(payload.count + 8).bigEndian
    result.append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
    result.append(payload)
    return result
}

let formats = [(16, "icp4"), (32, "icp5"), (64, "icp6"), (128, "ic07"),
               (256, "ic08"), (512, "ic09"), (1024, "ic10")]
let contents = formats.reduce(into: Data()) { data, format in
    data.append(chunk(format.1, containing: png(size: format.0)))
}
try chunk("icns", containing: contents).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
