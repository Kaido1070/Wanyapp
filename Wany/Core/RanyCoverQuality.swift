import Foundation
import CoreGraphics

enum RanyCoverQuality {
    static func signature(_ image: CGImage) -> UInt64? {
        var pixels = [UInt8](repeating:0,count:72)
        let success = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data:bytes.baseAddress,width:9,height:8,bitsPerComponent:8,bytesPerRow:9,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image,in:CGRect(x:0,y:0,width:9,height:8)); return true
        }
        guard success else { return nil }
        var hash: UInt64 = 0
        for y in 0..<8 { for x in 0..<8 {
            if pixels[y*9+x] > pixels[y*9+x+1] { hash |= UInt64(1) << (y*8+x) }
        } }
        return hash
    }
    static func matches(_ a: UInt64, _ b: UInt64) -> Bool { (a ^ b).nonzeroBitCount <= 3 }
    static func acceptsDimensions(width: Int, height: Int) -> Bool {
        let ratio = Double(width) / Double(max(1,height))
        // At least the staged size (432×595): a cover is never enlarged behind the content.
        return width >= 432 && height >= 595 && ratio >= 0.48 && ratio <= 0.88
    }
    // A conservative gate for blank, extremely soft and low-detail responses.
    // It deliberately prefers the reviewed offline set when a source is uncertain.
    static func hasDetail(_ image: CGImage) -> Bool {
        let width = 96, height = 132
        var pixels = [UInt8](repeating:0,count:width*height)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image,in:CGRect(x:0,y:0,width:CGFloat(width),height:CGFloat(height)))
            return true
        }
        guard rendered else { return false }
        var histogram = [Int](repeating:0,count:32)
        for pixel in pixels { histogram[Int(pixel)/8] += 1 }
        let count = Double(pixels.count)
        let entropy = histogram.filter { $0 > 0 }.reduce(0.0) { sum,n in let p = Double(n)/count; return sum-p*log2(p) }
        var edges = 0.0
        for y in 1..<(height-1) { for x in 1..<(width-1) {
            let i = y*width+x
            let laplacian = Double(4*Int(pixels[i])-Int(pixels[i-1])-Int(pixels[i+1])-Int(pixels[i-width])-Int(pixels[i+width]))
            edges += laplacian*laplacian
        } }
        return entropy >= 3.0 && edges/Double((width-2)*(height-2)) >= 100
    }
}
