import XCTest
import SwiftUI
import UIKit
@testable import Wany

@MainActor final class RanyGoldenOpeningTests: XCTestCase {
    func testCameraCompletesBeforeDistributionStarts() {
        XCTAssertEqual(RanyOpeningMotion.distribution(1.84),0)
        XCTAssertEqual(RanyOpeningMotion.camera(1.85),1,accuracy:0.000001)
        XCTAssertEqual(RanyOpeningMotion.distribution(1.85),0)
        XCTAssertEqual(RanyOpeningMotion.distribution(3.1),1,accuracy:0.000001)
        // Both ends have zero velocity; neither handoff kicks the artwork.
        XCTAssertLessThan(RanyOpeningMotion.glide(0.001),0.000001)
        XCTAssertLessThan(1-RanyOpeningMotion.glide(0.999),0.000001)
        XCTAssertEqual(Set(RanyOpeningMotion.originCells).count,14)
    }

    func testOfflineGoldenArtworkAndFinalHandoff() async throws {
        let images = try (1...14).map { try XCTUnwrap(UIImage(named:"RanyDefault\($0)")) }
        let palette = RanyOpeningPalette()
        await palette.prepare(images)
        let artwork = try XCTUnwrap(palette.artwork)
        XCTAssertEqual(artwork.original.count,14)
        XCTAssertEqual(artwork.toned.count,14)
        XCTAssertGreaterThanOrEqual(artwork.pages.count,13)
        var frames = Set<Data>()
        for time in [0.3,1.08,1.65,2.3,3.1,4.3] {
            let view = Canvas { context,size in
                RanyGoldenOpening.draw(context:context,size:size,time:time,artwork:artwork)
            }.frame(width:390,height:780)
            let renderer = ImageRenderer(content:view); renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            frames.insert(try XCTUnwrap(image.pngData()))
            let attachment = XCTAttachment(image:image)
            attachment.name = "Rany-golden-opening-\(time)s"
            attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(frames.count,6,"The montage, camera pullback and distribution must render distinct phases.")
        let before = ImageRenderer(content:Canvas { context,size in
            RanyGoldenOpening.draw(context:context,size:size,time:4.3,artwork:artwork)
        }.frame(width:390,height:780))
        let after = ImageRenderer(content:RanyBackdropArtwork(images:images,time:4.3,assembly:1).frame(width:390,height:780))
        before.scale = 1; after.scale = 1
        let a = try pixels(XCTUnwrap(before.uiImage)), b = try pixels(XCTUnwrap(after.uiImage))
        XCTAssertEqual(a.count,b.count)
        let error = zip(a,b).reduce(0.0) { $0+abs(Double($1.0)-Double($1.1)) }/Double(a.count)
        XCTAssertLessThan(error,1,"Ending the opening must preserve the original wallpaper's positions, sizes and opacity.")
        palette.release()
        XCTAssertNil(palette.artwork,"Temporary page sheets must be released after the opening.")
    }

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating:0,count:cg.width*cg.height*4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data:buffer.baseAddress,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:cg.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg,in:CGRect(x:0,y:0,width:CGFloat(cg.width),height:CGFloat(cg.height)))
        }
        return bytes
    }
}
