import XCTest
import UIKit
@testable import Wany

@MainActor final class CinematicTests: XCTestCase {
    func testBrandAndProductionGate() {
        let config=CinematicConfiguration()
        XCTAssertTrue(config.valid)
        XCTAssertEqual(config.fullBrandName,"Read Any Time")
        XCTAssertEqual(CinematicConfiguration.production.playback,.disabled)
        let glyphs=Array(config.displayTitle)
        XCTAssertEqual(config.retained.map { String(glyphs[$0]) }.joined(),RanyIdentity.displayName)
    }
    func testLogoUsesMeasuredFramesAcrossPhoneSizes() {
        for size in [CGSize(width:320,height:568),CGSize(width:393,height:852),CGSize(width:440,height:956),CGSize(width:852,height:393)] {
            for target in [CGRect(x:size.width-62,y:67,width:32,height:32),CGRect(x:size.width/2-46,y:110,width:92,height:92)] {
                let origin=CGPoint(x:0,y:10)
                let layout=CinematicLayout(size:size,origin:origin,destination:target,configuration:CinematicConfiguration())
                XCTAssertEqual(layout.logoPoint(4.8).x,target.midX,accuracy:0.01)
                XCTAssertEqual(layout.logoPoint(4.8).y,target.midY-origin.y,accuracy:0.01)
                XCTAssertEqual(layout.logoSize(4.8),target.width,accuracy:0.01)
                XCTAssertEqual(layout.cut(index:0,t:3.1),0)
                XCTAssertEqual(layout.cut(index:5,t:3.14),1)
                for t in stride(from:0.0,through:4.8,by:0.01) {
                    let point=layout.logoPoint(t)
                    XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                    XCTAssertGreaterThan(layout.logoSize(t),0)
                }
            }
        }
    }
    func testInterestsAndRecencyOutrankPopularFillerWithoutDuplicates() {
        func story(_ key: String,_ genre: String) -> Story { Story(key:key,source:"teamx",slug:key,type:"manhwa",url:"",title:key,cover:"https://example.invalid/cover.jpg",genres:[genre]) }
        let catalog=["reading":story("reading","action"),"favorite":story("favorite","fantasy"),"popular":story("popular","action"),"other":story("other","romance")]
        var data=AccountData(); data.favorites=["favorite","favorite"]
        data.library=[LibraryEntry(mangaId:"reading",status:"reading",addedAt:1,updatedAt:2,lastReadAt:3)]
        let keys=CinematicCoverPlan.keys(data:data,stories:catalog,interests:["favorite"],popular:["other","popular"])
        XCTAssertEqual(Set(keys).count,keys.count)
        XCTAssertTrue(Set(keys.prefix(2)).contains("reading")); XCTAssertTrue(Set(keys.prefix(2)).contains("favorite"))
        XCTAssertLessThan(keys.firstIndex(of:"popular")!,keys.firstIndex(of:"other")!)
    }
    func testMissingDestinationAndEmptyImagesHaveFiniteFallback() {
        let layout=CinematicLayout(size:CGSize(width:393,height:852),origin:.zero,destination:nil,configuration:CinematicConfiguration())
        XCTAssertEqual(layout.logoPoint(4.8),layout.logoPoint(3.5))
        let view=PageStage(images:[])
        view.frame=CGRect(x:0,y:0,width:393,height:852); view.layoutIfNeeded(); view.render(time:0,lighting:1,speed:1)
        XCTAssertNotNil(view.scene)
        view.scene=nil
    }
    func testBentPageShaderRendersBundledCoverPixels() throws {
        let cover=try XCTUnwrap(UIImage(named:"RanyDefault1"))
        let stage=PageStage(images:[cover])
        stage.frame=CGRect(x:0,y:0,width:320,height:568); stage.layoutIfNeeded()
        for time in [0.0,1.2,2.2] {
            stage.render(time:time,lighting:1,speed:1)
            let image=stage.snapshot()
            let cg=try XCTUnwrap(image.cgImage)
            var sample=[UInt8](repeating:0,count:16*16*4)
            sample.withUnsafeMutableBytes { bytes in
                let context=CGContext(data:bytes.baseAddress,width:16,height:16,bitsPerComponent:8,bytesPerRow:64,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(cg,in:CGRect(x:0,y:0,width:16,height:16))
            }
            let luminance=(0..<256).map { Int(sample[$0*4])+Int(sample[$0*4+1])+Int(sample[$0*4+2]) }
            XCTAssertGreaterThan(luminance.max() ?? 0,90,"A decoded cover must render, rather than a black SceneKit surface.")
            let attachment=XCTAttachment(image:image); attachment.name="Cinematic-page-\(time)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        stage.scene=nil
    }

}
