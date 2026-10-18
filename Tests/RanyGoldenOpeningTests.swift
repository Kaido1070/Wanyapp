import XCTest
import SwiftUI
import UIKit
import WebKit
@testable import Wany

@MainActor final class RanyGoldenOpeningTests: XCTestCase {
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
