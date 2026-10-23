import XCTest
import SwiftUI
import UIKit
@testable import Wany

@MainActor final class LogoAndImageQualityTests: XCTestCase {
    func testSystemLaunchUsesTheSameDarkSurfaceAsTheMark() throws {
        let launch=try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey:"UILaunchScreen") as? [String:Any])
        XCTAssertEqual(launch["UIColorName"] as? String,"RanyLaunchBackground")
        let color=try XCTUnwrap(UIColor(named:"RanyLaunchBackground"))
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        XCTAssertTrue(color.getRed(&r,green:&g,blue:&b,alpha:&a))
        XCTAssertEqual(r,23.0/255,accuracy:0.001);XCTAssertEqual(g,25.0/255,accuracy:0.001)
        XCTAssertEqual(b,27.0/255,accuracy:0.001);XCTAssertEqual(a,1,accuracy:0.001)
    }
    func testMarkTravelsFromCenterToMeasuredSafeAreaDestination() {
        for size in [CGSize(width:320,height:568),CGSize(width:430,height:932)] {
            let origin=CGPoint(x:0,y:18)
            let target=CGRect(x:size.width-61,y:79,width:32,height:32)
            let start=RanyLogoTimeline.frame(size:size,origin:origin,source:nil,destination:target,elapsed:0)
            XCTAssertEqual(start.midX,size.width/2,accuracy:0.01)
            XCTAssertEqual(start.midY,size.height/2,accuracy:0.01)
            let final=RanyLogoTimeline.frame(size:size,origin:origin,source:nil,destination:target,elapsed:2)
            XCTAssertEqual(final.width,target.width,accuracy:0.01)
            XCTAssertEqual(final.midY,target.midY-origin.y,accuracy:0.01)
            XCTAssertEqual(final.midX,target.midX,accuracy:0.01)
        }
    }
    func testMarkReducedMotionAndMissingDestinationAlwaysFinish() async throws {
        var reveals=0,finishes=0
        let root=RanyLogoIntro(reduceMotionOverride:true,onReveal:{reveals += 1},onFinish:{finishes += 1})
            .environment(\.scenePhase,.active)
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous=scene.windows.first { $0.isKeyWindow },window=UIWindow(windowScene:scene)
        window.frame=scene.coordinateSpace.bounds; window.rootViewController=UIHostingController(rootView:root); window.makeKeyAndVisible()
        defer { window.isHidden=true; window.rootViewController=nil; previous?.makeKeyAndVisible() }
        try await Task.sleep(for:.milliseconds(500))
        XCTAssertEqual(reveals,1); XCTAssertEqual(finishes,1)
    }
    func testArabicInterfaceDoesNotMirrorPhysicalLogoDestination() async throws {
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous=scene.windows.first { $0.isKeyWindow },window=UIWindow(windowScene:scene)
        window.frame=scene.coordinateSpace.bounds
        let width=window.bounds.width,height=window.bounds.height
        let root=RanyLogoIntro(destination:CGRect(x:width-60,y:80,width:32,height:32),onReveal:{},onFinish:{})
            .environment(\.scenePhase,.active).environment(\.layoutDirection,.rightToLeft)
        window.rootViewController=UIHostingController(rootView:root);window.makeKeyAndVisible()
        defer { window.isHidden=true;window.rootViewController=nil;previous?.makeKeyAndVisible() }
        try await Task.sleep(for:.milliseconds(1450))
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let image=UIGraphicsImageRenderer(size:window.bounds.size,format:format).image { _ in
            window.drawHierarchy(in:window.bounds,afterScreenUpdates:true)
        }
        let cg=try XCTUnwrap(image.cgImage),w=Int(width),h=Int(height)
        var bytes=[UInt8](repeating:0,count:w*h*4)
        let context=try XCTUnwrap(CGContext(data:&bytes,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(cg,in:CGRect(x:0,y:0,width:width,height:height))
        var count=0,totalX=0
        for y in 0..<h { for x in 0..<w {
            let i=(y*w+x)*4,r=Int(bytes[i]),g=Int(bytes[i+1]),b=Int(bytes[i+2])
            if r>140,g>100,b<190,r>g,g>b+10 { count+=1;totalX+=x }
        } }
        XCTAssertGreaterThan(count,10,"The official gold mark must render.")
        XCTAssertGreaterThan(Double(totalX)/Double(max(1,count)),Double(width)*0.65,"Global screen coordinates must remain physical in an Arabic interface.")
        let attachment=XCTAttachment(image:image);attachment.name="Rany-logo-physical-right-destination";attachment.lifetime = .keepAlways;add(attachment)
    }
    func testOriginalFilesAreByteIdenticalAndDecoderNeverUpscales() throws {
        let owner="quality-original-"+UUID().uuidString
        let url=Disk.file(owner,"page.png")
        let bytes=UIGraphicsImageRenderer(size:CGSize(width:20,height:30)).pngData { c in c.cgContext.setFillColor(UIColor.white.cgColor); c.cgContext.fill(CGRect(x:0,y:0,width:20,height:30)) }
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try bytes.write(to:url)
        XCTAssertEqual(try ImageStorage.compact(url,quality:.original),Int64(bytes.count))
        XCTAssertEqual(try Data(contentsOf:url),bytes)
        for quality in ImageQuality.allCases {
            XCTAssertLessThanOrEqual(quality.decodeFactor(width:4000,height:3000),1)
            XCTAssertEqual(quality.decodeFactor(width:200,height:300),1)
        }
        XCTAssertGreaterThan(ImageQuality.original.decodeFactor(width:4000,height:3000),ImageQuality.balanced.decodeFactor(width:4000,height:3000))
    }
    func testOriginalChoiceOverridesPreviouslyProxiedBalancedURL() throws {
        let api=API(configuration:.ephemeral,credential:"fixture",persistCredentials:false)
        let request=try api.imageRequest(source:"teamx",url:"https://wany.site/api/source/image?source=teamx&url=https%3A%2F%2Fexample.com%2Fpage.jpg&quality=balanced",quality:.original)
        let items=try XCTUnwrap(URLComponents(url:try XCTUnwrap(request.url),resolvingAgainstBaseURL:false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "quality" }?.value,"original")
        XCTAssertEqual(request.url?.host,"rany.lat","A saved URL on the old host is requested on the current origin, not through its redirect.")
        XCTAssertEqual(request.url?.path,"/api/source/image"); XCTAssertEqual(items.first { $0.name == "url" }?.value,"https://example.com/page.jpg")
    }
    func testQualityReplacementPreservesOfflineCopyUntilSuccessfulTransfer() throws {
        let downloads=Downloads.shared,oldOwner=downloads.owner,oldOnline=downloads.online
        downloads.online=false
        let owner="quality-replacement-"+UUID().uuidString
        let story=Story(key:"tx:quality-fixture",source:"teamx",slug:"fixture",type:"manga",url:"",title:"Fixture",cover:"",genres:[])
        let chapter=Chapter(number:1,title:"Chapter")
        let payload=ChapterPayload(item:story,number:1,title:"Chapter",pages:["https://example.com/page.png"])
        let name=Disk.imageName(payload.id,0),oldFile=Disk.file(owner,name)
        try FileManager.default.createDirectory(at:oldFile.deletingLastPathComponent(),withIntermediateDirectories:true)
        let oldBytes=Data([1,2,3,4]); try oldBytes.write(to:oldFile)
        let job=DownloadJob(id:story.key,story:story,chapters:[ChapterDownload(chapter:chapter,payload:payload,images:[ImageRecord(remote:payload.pages[0],file:name,bytes:4,done:true,quality:"balanced")])],wholeStory:false,chapterListComplete:true)
        try Disk.save([job],owner:owner,name:"downloads.json")
        downloads.attach(owner)
        defer { downloads.remove(story.key); downloads.attach(oldOwner); downloads.online=oldOnline }
        downloads.redownload(payload,quality:.original)
        XCTAssertEqual(downloads.pageURL(payload,index:0),oldFile)
        let record=try XCTUnwrap(downloads.jobs.first?.chapters.first?.images.first)
        XCTAssertNotEqual(record.file,name); XCTAssertEqual(record.fallbackFile,name)
        let late=TransferTag(owner:owner,job:story.key,chapter:"1",image:name,quality:"balanced")
        downloads.didFinish(late,bytes:0,error:"cancelled",optimized:false)
        XCTAssertEqual(try Data(contentsOf:oldFile),oldBytes)
        let tag=TransferTag(owner:owner,job:story.key,chapter:"1",image:record.file,quality:"original")
        downloads.didFinish(tag,bytes:0,error:"offline",optimized:false)
        XCTAssertEqual(downloads.pageURL(payload,index:0),oldFile)
        let newFile=Disk.file(owner,record.file),newBytes=Data([5,6,7,8,9])
        try newBytes.write(to:newFile)
        downloads.didFinish(tag,bytes:Int64(newBytes.count),error:nil,optimized:false)
        XCTAssertEqual(downloads.pageURL(payload,index:0),newFile)
        XCTAssertEqual(try Data(contentsOf:newFile),newBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath:oldFile.path))
        XCTAssertTrue(downloads.jobs.first?.complete == true)
    }
    func testChangingDecodedQualityKeepsZoomAndScrollPosition() {
        let scroll=ChapterScroll(frame:CGRect(x:0,y:0,width:320,height:500))
        scroll.configure(id:"fixture",urls:[nil,nil],ratios:[0:2,1:2],initialPage:0,nextTitle:nil,online:false)
        scroll.layoutIfNeeded(); scroll.setZoomScale(2,animated:false)
        scroll.setContentOffset(CGPoint(x:40,y:180),animated:false)
        let offset=scroll.contentOffset,zoom=scroll.zoomScale
        scroll.configure(id:"fixture",urls:[nil,nil],ratios:[0:2,1:2],initialPage:0,nextTitle:nil,online:false,quality:.original)
        scroll.layoutIfNeeded()
        XCTAssertEqual(scroll.zoomScale,zoom,accuracy:0.01)
        XCTAssertEqual(scroll.contentOffset.y,offset.y,accuracy:0.1)
    }
}
