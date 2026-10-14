import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageQuality: String, CaseIterable, Identifiable {
    case balanced, high, original
    var id: String { rawValue }
    var label: String { switch self { case .balanced: return "متوازنة"; case .high: return "عالية"; case .original: return "أصلية" } }
    var width: Double { self == .balanced ? 1440 : 2000 }
    var compression: Double { self == .balanced ? 0.82 : 0.92 }
}

enum ImageStorage {
    // Write a smaller candidate first; never replace a valid image with a larger or invalid file.
    static func compact(_ url: URL, quality: ImageQuality) throws -> Int64 {
        let original = (try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard quality != .original, let source = CGImageSourceCreateWithURL(url as CFURL,nil),
              CGImageSourceGetCount(source) == 1,
              let info = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = info[kCGImagePropertyPixelWidth] as? Double,
              let height = info[kCGImagePropertyPixelHeight] as? Double, width > 0, height > 0 else { return original }
        let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:min(32000,max(width,height)*min(1,quality.width/width))]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else { return original }
        // Keep transparent images intact rather than changing their background.
        guard image.alphaInfo == .none || image.alphaInfo == .noneSkipFirst || image.alphaInfo == .noneSkipLast else { return original }
        let candidate = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString+".jpg")
        defer { try? FileManager.default.removeItem(at:candidate) }
        guard let destination = CGImageDestinationCreateWithURL(candidate as CFURL,UTType.jpeg.identifier as CFString,1,nil) else { return original }
        CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:quality.compression] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return original }
        let size = (try FileManager.default.attributesOfItem(atPath:candidate.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size < original,
              let check = CGImageSourceCreateWithURL(candidate as CFURL,nil), CGImageSourceCreateImageAtIndex(check,0,nil) != nil else { return original }
        let bytes = try Data(contentsOf:candidate)
        try bytes.write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        return size
    }
}
