import CoreGraphics
import Foundation
import ImageIO

enum ArtworkHasher {
    static func hash(hexDescriptor path: String) -> UInt64? {
        guard
            let descriptor = try? String(contentsOfFile: path, encoding: .utf8),
            let opening = descriptor.range(of: "$(", options: .backwards),
            let closing = descriptor.lastIndex(of: ")"),
            opening.upperBound < closing
        else {
            return nil
        }
        let hex = String(descriptor[opening.upperBound..<closing])
        guard !hex.isEmpty, hex.count.isMultiple(of: 2) else { return nil }

        var data = Data()
        data.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        return hash(imageData: data)
    }

    static func hash(imageData: Data) -> UInt64? {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let context = CGContext(
                data: nil,
                width: 9,
                height: 8,
                bitsPerComponent: 8,
                bytesPerRow: 9,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
        guard let buffer = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        var bits: UInt64 = 0
        for row in 0..<8 {
            for column in 0..<8 {
                let left = buffer[row * 9 + column]
                let right = buffer[row * 9 + column + 1]
                bits <<= 1
                if left > right {
                    bits |= 1
                }
            }
        }
        return bits
    }

    static func similarity(_ first: UInt64, _ second: UInt64) -> Double {
        let difference = (first ^ second).nonzeroBitCount
        return 1.0 - Double(difference) / 64.0
    }
}
