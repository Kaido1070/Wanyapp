import XCTest
import SwiftUI
import UIKit
import WebKit
@testable import Wany

@MainActor final class RanyGoldenOpeningTests: XCTestCase {
    func testTypographySharesApprovedBackgroundBeatsWithoutSkippingReadableHolds() {
        XCTAssertEqual(RanyOpeningTimeline.typographyTime(elapsed:-1),0)
        XCTAssertEqual(RanyOpeningTimeline.typographyTime(elapsed:1.85),2.3,accuracy:0.001)
        XCTAssertEqual(RanyOpeningTimeline.typographyTime(elapsed:3.1),3.4,accuracy:0.001)
        XCTAssertEqual(RanyOpeningTimeline.typographyTime(elapsed:4.3),4.8,accuracy:0.001)
        var previous=0.0
        for time in stride(from:0.0,through:5,by:0.01) {
            let current=RanyOpeningTimeline.typographyTime(elapsed:time)
            XCTAssertGreaterThanOrEqual(current,previous)
            XCTAssertLessThan(current-previous,0.04,"A delayed frame must sample a continuous timeline, not jump between staged animations.")
            previous=current
        }
        let layout=CinematicLayout(size:CGSize(width:390,height:780),origin:.zero,destination:nil,configuration:CinematicConfiguration(),centerFraction:0.44)
        for time in [1.85,2.0,2.2,2.35] {
            for index in CinematicConfiguration().retained {
                XCTAssertEqual(layout.cut(index:index,t:RanyOpeningTimeline.typographyTime(elapsed:time)),0)
            }
        }
    }

    func testOpeningGoldRemainsReadableOverBrightArtwork() throws {
        let size=CGSize(width:390,height:780)
        let layout=CinematicLayout(size:size,origin:.zero,destination:nil,configuration:CinematicConfiguration(),centerFraction:0.44)
        let renderer=ImageRenderer(content:ZStack {
            Color.white
            CinematicTypography(t:0.8,layout:layout,configuration:CinematicConfiguration())
        }.frame(width:size.width,height:size.height))
        renderer.scale=1
        let image=try XCTUnwrap(renderer.uiImage), data=try pixels(image)
        var red:CGFloat=0,green:CGFloat=0,blue:CGFloat=0,alpha:CGFloat=0
        UIColor(RanyTypography.brandColor).getRed(&red,green:&green,blue:&blue,alpha:&alpha)
        let gold=[Double(red)*255,Double(green)*255,Double(blue)*255]
        func luminance(_ components:[Double]) -> Double {
            let linear=components.map { value -> Double in let v=value/255; return v<=0.04045 ? v/12.92 : pow((v+0.055)/1.055,2.4) }
            return linear[0]*0.2126+linear[1]*0.7152+linear[2]*0.0722
        }
        let ink=luminance(gold)
        var checked=0,readable=0
        for y in 8..<772 {
            for x in 8..<382 {
                let offset=(y*390+x)*4
                guard (0..<3).allSatisfy({ abs(Double(data[offset+$0])-gold[$0])<10 }) else { continue }
                var background=0.0,found=false
                for (dx,dy) in [(-6,0),(6,0),(0,-6),(0,6)] {
                    let index=((y+dy)*390+x+dx)*4
                    let values=(0..<3).map { Double(data[index+$0]) }
                    if (values.max() ?? 0)-(values.min() ?? 0)<3 {
                        background=max(background,luminance(values)); found=true
                    }
                }
                if found { checked+=1; if (ink+0.05)/(background+0.05)>=3 { readable+=1 } }
            }
        }
        XCTAssertGreaterThan(checked,50,"The original gold lettering must actually render.")
        XCTAssertGreaterThan(Double(readable)/Double(max(1,checked)),0.95,"Large title strokes need at least 3:1 local contrast even on white covers.")
        let attachment=XCTAttachment(image:image); attachment.name="Rany-gold-title-white-artwork"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testCanvasHoldsItsFirstPageUntilNativeTitleIsReady() async throws {
        let covers=try (1...14).map { try XCTUnwrap(UIImage(named:"RanyDefault\($0)")) }
        let prepared=expectation(description:"Static page prepared"), started=expectation(description:"Joint opening starts")
        var didPrepare=false,didStart=false
        let root=RanyApprovedBackground(images:covers,accountID:nil,canStart:true,playOpening:true,typographyReady:false,onPrepared:{
            if !didPrepare { didPrepare=true; prepared.fulfill() }
        },onStarted:{ _ in if !didStart { didStart=true; started.fulfill() } },onFailure:{ XCTFail("The opening preparation must succeed.") })
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous=scene.windows.first { $0.isKeyWindow },window=UIWindow(windowScene:scene)
        window.frame=scene.coordinateSpace.bounds;window.rootViewController=UIHostingController(rootView:root);window.makeKeyAndVisible()
        defer { window.isHidden=true;window.rootViewController=nil;previous?.makeKeyAndVisible() }
        await fulfillment(of:[prepared],timeout:25)
        func descendants(_ view:UIView)->[UIView] { [view]+view.subviews.flatMap(descendants) }
        let web=try XCTUnwrap(descendants(window).compactMap { $0 as? WKWebView }.first)
        try await Task.sleep(for:.milliseconds(500))
        let heldValue=try await approvedJavaScript(web,"return window.RanyBackground.state()")
        let held=try XCTUnwrap(heldValue as? [String:Any])
        XCTAssertEqual(held["started"] as? Bool,false)
        XCTAssertEqual(held["openingStarts"] as? Int,0)
        XCTAssertEqual(held["time"] as? Double,0)
        _ = try await approvedJavaScript(web,"window.RanyBackground.setTypographyReady(true); return true")
        await fulfillment(of:[started],timeout:10)
        let runningValue=try await approvedJavaScript(web,"return window.RanyBackground.state()")
        let running=try XCTUnwrap(runningValue as? [String:Any])
        XCTAssertEqual(running["openingStarts"] as? Int,1)
    }

    func testAnonymousPoolBecomesReadyWithoutNetworkAndSurvivesReattach() async {
        let ambience = RanyAmbience()
        XCTAssertFalse(ambience.openingReady)
        await ambience.attach(state:nil,stories:[:])
        XCTAssertTrue(ambience.openingReady)
        let first = ambience.images.map(ObjectIdentifier.init)
        await ambience.attach(state:nil,stories:[:])
        XCTAssertEqual(ambience.images.map(ObjectIdentifier.init),first)
    }

    func testBundledDrawingIsTheUnmodifiedApprovedSource() throws {
        let actualURL = try XCTUnwrap(Bundle.main.url(forResource:"RanyApprovedBackground",withExtension:"html"))
        let referenceURL = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"rany-gold-smooth-transition",withExtension:"html"))
        let actual = try String(contentsOf:actualURL,encoding:.utf8)
        let reference = try String(contentsOf:referenceURL,encoding:.utf8)
        let start = try XCTUnwrap(reference.range(of:"const W=390"))
        let end = try XCTUnwrap(reference.range(of:"function tick(now)"))
        let expected = String(reference[start.lowerBound..<end.lowerBound])
        let embedded = try XCTUnwrap(actual.components(separatedBy:"// BEGIN UNMODIFIED APPROVED DRAWING\n").last?.components(separatedBy:"// END UNMODIFIED APPROVED DRAWING").first)
        XCTAssertEqual(embedded,expected,"The selected artwork must not be replaced by an approximate renderer.")
        XCTAssertFalse(actual.contains("https://"))
        XCTAssertFalse(actual.contains("<button"))
    }

    func testActualBackgroundMatchesApprovedReferenceAtEveryPhase() async throws {
        let images = try (1...14).map { try XCTUnwrap(UIImage(named:"RanyDefault\($0)")) }
        let started = expectation(description:"Approved background first frame")
        var didStart = false
        let root = RanyApprovedBackground(images:images,accountID:nil,canStart:true,playOpening:true,onStarted:{ _ in
            if !didStart { didStart = true; started.fulfill() }
        },onFailure:{ XCTFail("The bundled offline approved background must load."); if !didStart { didStart = true; started.fulfill() } })
            .frame(width:390,height:780).ignoresSafeArea()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene:scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView:root)
        window.makeKeyAndVisible(); window.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        await fulfillment(of:[started],timeout:25)
        func descendants(_ view: UIView) -> [UIView] { [view]+view.subviews.flatMap(descendants) }
        let web = try XCTUnwrap(descendants(window).compactMap { $0 as? WKWebView }.first)
        XCTAssertEqual(web.bounds.width,390,accuracy:1)
        XCTAssertEqual(web.bounds.height,780,accuracy:1)
        for time in [0.3,0.8,1.08,1.65,2.4,3.1,4.3] {
            _ = try await approvedJavaScript(web,"return await window.RanyBackground.freeze(time)",arguments:["time":time])
            let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage,Error>) in
                let configuration = WKSnapshotConfiguration(); configuration.afterScreenUpdates = true
                web.takeSnapshot(with:configuration) { image,error in
                    if let image { continuation.resume(returning:image) }
                    else { continuation.resume(throwing:error ?? NSError(domain:"RanySnapshot",code:1)) }
                }
            }
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let normalized = UIGraphicsImageRenderer(size:CGSize(width:390,height:780),format:format).image { _ in snapshot.draw(in:CGRect(x:0,y:0,width:390,height:780)) }
            let name = "approved-"+String(time).replacingOccurrences(of:".",with:"_")
            let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:name,withExtension:"png"))
            let reference = try XCTUnwrap(UIImage(contentsOfFile:url.path))
            let a = try pixels(normalized), b = try pixels(reference)
            guard a.count == b.count else { XCTFail("Reference dimensions differ."); continue }
            var error = 0.0
            for index in a.indices where index%4 != 3 { error += abs(Double(a[index])-Double(b[index])) }
            error /= Double(a.count/4*3)
            XCTAssertLessThan(error,8,"Approved reference differs at \(time)s (mean RGB error \(error)).")
            let attachment = XCTAttachment(image:normalized); attachment.name = "Rany-approved-native-\(time)s"; attachment.lifetime = .keepAlways; add(attachment)
            let expected = XCTAttachment(image:reference); expected.name = "Rany-approved-reference-\(time)s"; expected.lifetime = .keepAlways; add(expected)
        }
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

@MainActor func approvedJavaScript(_ web: WKWebView,_ script: String,arguments: [String:Any] = [:]) async throws -> Any {
    try await withCheckedThrowingContinuation { continuation in
        web.callAsyncJavaScript(script,arguments:arguments,in:nil,in:.page) { result in continuation.resume(with:result) }
    }
}
