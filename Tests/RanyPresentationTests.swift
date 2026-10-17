import XCTest
import SwiftUI
import UIKit
@testable import Wany

@MainActor final class RanyPresentationTests: XCTestCase {
    private func fixtureStore() -> AppStore {
        let store = AppStore(startServices:false)
        store.online = false
        var state = AccountState(user:Account(id:"visual-regression",name:"Rany Reader",username:"reader"))
        for i in 0..<16 {
            let key = "preview-\(i)"
            state.data.library.append(LibraryEntry(mangaId:key,status:"reading",addedAt:1,updatedAt:1))
            store.stories[key] = Story(key:key,source:"teamx",slug:key,type:"manhwa",url:"",title:"Story \(i+1)",cover:"",genres:[])
        }
        store.state = state
        return store
    }
    func testHeaderBelongsToContentAndDoesNotReturnHalfwayUp() async throws {
        let store = fixtureStore(), ambience = RanyAmbience()
        var mark: CGRect = .zero
        let root = ZStack {
            RanyBackdropHost(ambience:ambience,reading:false,accountID:nil,assembly:1).frame(maxWidth:.infinity,maxHeight:.infinity).ignoresSafeArea()
            RootView().environment(\.ranyMeasureMarkFrames,true)
        }.environmentObject(store).environmentObject(store.downloads)
            .environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark).tint(Theme.accent)
            .onPreferenceChange(RanyMarkFrameKey.self) { frames in if let frame = frames["header"] { mark = frame } }
        let (window,previous) = show(root)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds:1_200_000_000)
        let start = mark
        XCTAssertGreaterThan(start.width,0)
        XCTAssertGreaterThan(start.midX,window.bounds.midX)
        let scroll = try XCTUnwrap(descendants(window).compactMap { $0 as? UIScrollView }.first { $0.contentSize.height > $0.bounds.height+700 })
        snapshot(window,name:"Rany-profile-glass")
        assertBackgroundIsVisible(window)
        XCTAssertEqual(descendants(window).filter { $0.accessibilityIdentifier == "rany.background.renderer" }.count,1)
        scroll.setContentOffset(CGPoint(x:0,y:700-scroll.adjustedContentInset.top),animated:false)
        try await Task.sleep(nanoseconds:250_000_000)
        XCTAssertLessThan(mark.maxY,0,"The header must leave with the page, without changing navigation-bar insets.")
        scroll.setContentOffset(CGPoint(x:0,y:350-scroll.adjustedContentInset.top),animated:false)
        try await Task.sleep(nanoseconds:250_000_000)
        XCTAssertLessThan(mark.maxY,0,"A partial upward scroll must not summon the header.")
        scroll.setContentOffset(CGPoint(x:0,y:-scroll.adjustedContentInset.top),animated:false)
        try await Task.sleep(nanoseconds:250_000_000)
        XCTAssertEqual(mark.minY,start.minY,accuracy:2)
        XCTAssertEqual(descendants(window).filter { $0.accessibilityIdentifier == "rany.background.renderer" }.count,1)
    }
    func testSettingsKeepsTheSameSceneVisible() async throws {
        let store = fixtureStore(), ambience = RanyAmbience()
        let root = ZStack {
            RanyBackdropHost(ambience:ambience,reading:false,accountID:nil,assembly:1).frame(maxWidth:.infinity,maxHeight:.infinity).ignoresSafeArea()
            NavigationStack { SettingsView().ranyClearNavigation() }
        }.environmentObject(store).environmentObject(store.downloads)
            .environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark).tint(Theme.accent)
        let (window,previous) = show(root)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds:1_200_000_000)
        assertBackgroundIsVisible(window)
        snapshot(window,name:"Rany-settings-appearance")
    }
    private func show<V: View>(_ root: V) -> (UIWindow,UIWindow?) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene:scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView:root)
        window.makeKeyAndVisible(); window.layoutIfNeeded()
        return (window,previous)
    }
    private func descendants(_ view: UIView) -> [UIView] { [view]+view.subviews.flatMap(descendants) }
    private func image(_ window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(bounds:window.bounds,format:format).image { _ in window.drawHierarchy(in:window.bounds,afterScreenUpdates:true) }
    }
    private func snapshot(_ window: UIWindow, name: String) {
        let attachment = XCTAttachment(image:image(window)); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func assertBackgroundIsVisible(_ window: UIWindow, file: StaticString = #filePath, line: UInt = #line) {
        let rendered = image(window).cgImage!
        var pixels = [UInt8](repeating:0,count:4)
        let sample = rendered.cropping(to:CGRect(x:14,y:CGFloat(rendered.height/2),width:1,height:1))!
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data:bytes.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(sample,in:CGRect(x:0,y:0,width:1,height:1))
        }
        XCTAssertGreaterThan(Int(pixels[0])+Int(pixels[1])+Int(pixels[2]),25,"An opaque black navigation container is covering the shared wallpaper.",file:file,line:line)
    }
}
