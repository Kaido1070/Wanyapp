import XCTest
import UIKit
import SceneKit
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
    func testRanyAndRHaveDistinctReadableHoldsBeforeOfficialWipe() {
        let config=CinematicConfiguration()
        let layout=CinematicLayout(size:CGSize(width:393,height:852),origin:.zero,destination:nil,configuration:config)
        for t in [2.3,2.4,2.5,2.6,2.7] {
            for index in config.retained { XCTAssertEqual(layout.cut(index:index,t:t),0) }
            XCTAssertEqual(layout.point(index:0,t:t),layout.point(index:0,t:2.3))
        }
        for t in [3.16,3.2,3.3,3.4] {
            for index in config.retained.dropFirst() { XCTAssertEqual(layout.cut(index:index,t:t),1) }
            XCTAssertEqual(layout.point(index:0,t:t).x,196.5,accuracy:0.01)
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
    func testRecycledPageKeepsItsPoseAcrossConsecutiveTurnBoundaries() throws {
        let cover=try XCTUnwrap(UIImage(named:"RanyDefault1"))
        let stage=PageStage(images:Array(repeating:cover,count:8))
        stage.frame=CGRect(x:0,y:0,width:320,height:568); stage.layoutIfNeeded()
        @MainActor func page(_ id: Int) throws -> SCNNode {
            try XCTUnwrap(stage.scene?.rootNode.childNodes.first { $0.name == String(id) && $0.geometry?.firstMaterial?.shaderModifiers?.isEmpty == false })
        }
        for boundary in 1...5 {
            let time=0.45+2.7*pow(Double(boundary)/18,1/1.6)
            stage.render(time:time-0.00005,lighting:1,speed:1)
            let before=try page(boundary-1), position=before.position, roll=before.eulerAngles.z
            let turn=try XCTUnwrap(before.geometry?.firstMaterial?.value(forKey:"turn") as? NSNumber).doubleValue
            stage.render(time:time+0.00005,lighting:1,speed:1)
            let after=try page(boundary-1)
            XCTAssertFalse(after.isHidden)
            XCTAssertEqual(after.position.x,position.x,accuracy:0.015)
            XCTAssertEqual(after.eulerAngles.z,roll,accuracy:0.001)
            XCTAssertEqual(try XCTUnwrap(after.geometry?.firstMaterial?.value(forKey:"turn") as? NSNumber).doubleValue,turn,accuracy:0.005,"An outgoing cover must keep its bend when recycled into the next mesh, rather than pop back into the center.")
        }
        stage.scene=nil
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
            var luminance: [Int] = []
            for pixel in 0..<256 {
                let red: Int = Int(sample[pixel*4]), green: Int = Int(sample[pixel*4+1]), blue: Int = Int(sample[pixel*4+2])
                luminance.append(red+green+blue)
            }
            XCTAssertGreaterThan(luminance.max() ?? 0,90,"A decoded cover must render, rather than a black SceneKit surface.")
            let attachment=XCTAttachment(image:image); attachment.name="Cinematic-page-\(time)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        stage.scene=nil
    }

}
