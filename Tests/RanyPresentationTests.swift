import XCTest
import SwiftUI
import UIKit
import WebKit
@testable import Wany

@MainActor final class RanyPresentationTests: XCTestCase {
    func testVisibleReadingToolsFitSmallAndLargePhones() throws {
        for width in [320.0,430.0] {
            let content=VStack(spacing:18) {
                StoryReadingTools(canReadAll:true,disabled:false,markAll:{},clear:{})
                ForEach([false,true],id:\.self) { completed in
                    VStack(alignment:.leading,spacing:8) {
                        Text("الفصل ١١٩٦ · بداية المغامرة").font(RanyTypography.font(.subheadline))
                        ChapterReadingTools(completed:completed,disabled:false,markRead:{},markUnread:{})
                    }.padding(14).ranyInsetGlass(radius:12)
                }
            }.padding(16).frame(width:width).fixedSize(horizontal:false,vertical:true)
                .environment(\.layoutDirection,.rightToLeft)
                .environment(\.colorScheme,.dark)
                .background(Theme.background)
            let renderer=ImageRenderer(content:content)
            renderer.proposedSize=ProposedViewSize(width:width,height:nil)
            let rendered=try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(rendered.size.width,width,accuracy:1)
            let attachment=XCTAttachment(image:rendered)
            attachment.name="Rany-visible-reading-tools-\(Int(width))"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testAvatarGridFitsCompactPhoneWithoutWastefulRows() async throws {
        let store = fixtureStore()
        let avatars: [JSONValue] = (0..<16).map { index in
            .object(["id":.string("fixture-\(index)"),"characterName":.string("Character \(index)")])
        }
        let series: [JSONValue] = [.object(["name":.string("ONE PIECE"),"avatars":.array(avatars)])]
        let grid = VStack(alignment:.leading) {
            RanyAvatarGrid(series:series,query:"",selectedID:"fixture-0",select:{ _ in })
        }.padding(16).frame(width:320).fixedSize(horizontal:false,vertical:true)
            .environmentObject(store).environment(\.layoutDirection,.rightToLeft)
        let renderer = ImageRenderer(content:grid)
        renderer.proposedSize = ProposedViewSize(width:320,height:nil)
        let rendered = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(rendered.size.width,320,accuracy:1)
        XCTAssertGreaterThan(rendered.size.height,500)
        XCTAssertLessThan(rendered.size.height,900,"Six compact grid rows should replace sixteen full-width rows.")
        let attachment = XCTAttachment(image:rendered)
        attachment.name = "Rany-avatar-grid-320"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testProductionGoldenOpeningWaitsForActiveSceneThenPlaysOnce() async throws {
        let store = fixtureStore(), fixture = CinematicLifecycleFixture()
        fixture.phase = .inactive
        var starts: [Date] = []
        let root = GoldenProductionLifecycleView(fixture:fixture,store:store,onStart:{ starts.append($0) })
        let (window,previous) = show(root)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        // Exceed the entire intro duration while inactive: cold launch must not consume it.
        try await Task.sleep(for:.seconds(4.6))
        XCTAssertTrue(starts.isEmpty)
        let waiting = try XCTUnwrap(image(window).cgImage)
        let sample = try XCTUnwrap(waiting.cropping(to:CGRect(x:CGFloat(waiting.width)/2,y:CGFloat(waiting.height)*0.35,width:1,height:1)))
        var pixel = [UInt8](repeating:0,count:4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data:bytes.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(sample,in:CGRect(x:0,y:0,width:1,height:1))
        }
        for (actual,expected) in zip(pixel.prefix(3),[23,25,27]) {
            XCTAssertEqual(Double(actual),Double(expected),accuracy:3,"Preparing the opening must show the theme, never the old colored cover cluster.")
        }
        fixture.phase = .active
        for _ in 0..<200 {
            if !starts.isEmpty { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        if starts.isEmpty {
            snapshot(window,name:"Rany-production-start-failure")
            if let web = descendants(window).compactMap({ $0 as? WKWebView }).first {
                let state = try await approvedJavaScript(web,"return window.RanyBackground.state()")
                XCTFail("Production background did not start: \(state), hidden=\(web.isHidden), frame=\(web.frame)")
            }
        }
        let started = try XCTUnwrap(starts.first,"The production host must prepare and start the golden background.")
        for (time,name) in [(0.12,"0_12s"),(0.25,"0_25s"),(0.5,"0_50s"),(0.8,"0_80s"),(1.08,"1_08s"),(1.3,"1_30s"),(1.65,"1_65s"),(2.05,"2_05s"),(2.4,"distribution"),(2.85,"R"),(3.4,"mark"),(4.6,"handoff")] {
            let remaining = time-Date().timeIntervalSince(started)
            if remaining > 0 { try await Task.sleep(for:.seconds(remaining)) }
            snapshot(window,name:"Rany-production-golden-\(name)")
        }
        XCTAssertEqual(descendants(window).filter { $0.accessibilityIdentifier == "rany.background.renderer" }.count,1)
        fixture.phase = .inactive
        try await Task.sleep(for:.milliseconds(100))
        fixture.phase = .active
        try await Task.sleep(for:.milliseconds(300))
        XCTAssertEqual(starts.count,1,"Returning to the app must not replay the opening.")
        let web = try XCTUnwrap(descendants(window).compactMap { $0 as? WKWebView }.first)
        let value = try await approvedJavaScript(web,"return window.RanyBackground.state()")
        let state = try XCTUnwrap(value as? [String:Any])
        XCTAssertEqual(state["openingStarts"] as? Int,1)
        XCTAssertGreaterThanOrEqual(state["time"] as? Double ?? 0,4.3)
    }

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
        XCTAssertTrue(store.mainPageVisible,"Scrolling must keep the main navigation visible.")
        XCTAssertFalse(store.readerActive)
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
    func testAuthScreensRemainReadableWithTheSharedWallpaper() async throws {
        let store = fixtureStore(), ambience = RanyAmbience()
        store.state = nil
        for creating in [false,true] {
            let root = ZStack {
                RanyBackdropHost(ambience:ambience,reading:false,accountID:nil,assembly:1).ignoresSafeArea()
                RanyLoginView(creatingAccount:creating)
            }.environmentObject(store).environmentObject(store.downloads)
                .environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark)
            let (window,previous) = show(root)
            try await Task.sleep(nanoseconds:1_400_000_000)
            assertBackgroundIsVisible(window)
            snapshot(window,name:creating ? "Rany-create-account" : "Rany-login")
            window.isHidden = true; previous?.makeKeyAndVisible()
        }
    }
    func testCompletedNativePushAndPopRestoreMainBar() async throws {
        let store = fixtureStore()
        let root = RootView().environmentObject(store).environmentObject(store.downloads)
            .environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark)
        let (window,previous) = show(root)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds:700_000_000)
        func navigation(_ controller: UIViewController) -> UINavigationController? {
            if let nav = controller as? UINavigationController { return nav }
            return controller.children.compactMap(navigation).first
        }
        let nav = try XCTUnwrap(navigation(window.rootViewController!))
        XCTAssertTrue(store.mainPageVisible)
        let child = ActivityView().background(RanyNavigationLifecycle(main:false))
            .environmentObject(store).environmentObject(store.downloads)
        nav.pushViewController(UIHostingController(rootView:child),animated:true)
        try await Task.sleep(nanoseconds:900_000_000)
        XCTAssertFalse(store.mainPageVisible)
        snapshot(window,name:"Rany-activity-after-transition")
        nav.popViewController(animated:true)
        try await Task.sleep(nanoseconds:900_000_000)
        // The bar is now attached to the root destination itself, rather than relying
        // on a delayed global visibility boolean from the popped destination.
        XCTAssertEqual(nav.viewControllers.count,1,"A completed pop must restore the native root containing the tab bar.")
        snapshot(window,name:"Rany-main-bar-after-pop")
    }
    func testFirstAccountIntroCompletesItsAssemblyAndHandoff() async throws {
        var arranged = false, revealed = false, finished = false
        let root = RanyIntro(accountTransition:true,loginDestination:false,firstAccount:true,
            onArrange:{ arranged = true },onReveal:{ revealed = true },onFinish:{ finished = true })
            .preferredColorScheme(.dark)
        let (window,previous) = show(root)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds:1_200_000_000)
        snapshot(window,name:"Rany-first-account-RANY")
        try await Task.sleep(nanoseconds:1_500_000_000)
        snapshot(window,name:"Rany-first-account-mark")
        try await Task.sleep(nanoseconds:2_000_000_000)
        XCTAssertTrue(arranged); XCTAssertTrue(revealed); XCTAssertTrue(finished)
    }
    func testSignedInCinematicPreviewPlaysBeforeHandoffAndReleasesPages() async throws {
        let store=fixtureStore()
        let (window,previous)=show(CinematicPreview().environmentObject(store))
        defer { window.isHidden=true; previous?.makeKeyAndVisible() }
        for _ in 0..<100 {
            if descendants(window).contains(where:{ $0 is PageStage }) { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        let stage=try XCTUnwrap(descendants(window).compactMap { $0 as? PageStage }.first,"The account snapshot must be attached before the intro starts, rather than cancelling it as an account switch.")
        for _ in 0..<70 {
            if stage.firstFrameReady { break }
            try await Task.sleep(for:.milliseconds(100))
        }
        XCTAssertTrue(stage.firstFrameReady)
        let started=try XCTUnwrap(stage.firstFrameTimestamp)
        @MainActor func waitUntil(_ time: Double) async throws {
            let remaining=time-Date().timeIntervalSince(started)
            if remaining>0 { try await Task.sleep(nanoseconds:UInt64(remaining*1_000_000_000)) }
        }
        snapshot(window,name:"Rany-cinematic-first-frame")
        try await waitUntil(0.8)
        snapshot(window,name:"Rany-cinematic-Read-Any-Time")
        try await waitUntil(2.4)
        snapshot(window,name:"Rany-cinematic-RANY")
        try await waitUntil(3.17)
        snapshot(window,name:"Rany-cinematic-R")
        try await waitUntil(3.85)
        snapshot(window,name:"Rany-cinematic-official-mark")
        try await waitUntil(5.4)
        XCTAssertFalse(descendants(window).contains { $0 is PageStage },"The optional renderer must release after the handoff.")
        snapshot(window,name:"Rany-cinematic-signed-in-handoff")
    }
    func testPreviewClearsAccountArtworkBeforeDismissalOnOwnerChange() async throws {
        let store=fixtureStore()
        let (window,previous)=show(CinematicPreview().environmentObject(store))
        defer { window.isHidden=true; previous?.makeKeyAndVisible() }
        for _ in 0..<100 {
            if descendants(window).contains(where:{ $0 is PageStage }) { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        let stage=try XCTUnwrap(descendants(window).compactMap { $0 as? PageStage }.first)
        // Creating the UIView is earlier than its first GPU frame. Switch owners
        // during actual playback, after SwiftUI has committed the initial snapshot.
        for _ in 0..<70 {
            if stage.firstFrameReady { break }
            try await Task.sleep(for:.milliseconds(100))
        }
        XCTAssertTrue(stage.firstFrameReady,"The privacy check must exercise rendered account artwork.")
        store.state=AccountState(user:Account(id:"another-preview-owner",name:"B",username:"fixture-b"))
        // Observe removal across render transactions instead of assuming that a
        // fixed 300ms sleep necessarily commits a SwiftUI update on a busy runner.
        for _ in 0..<20 {
            if !descendants(window).contains(where:{ $0 is PageStage }) { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        XCTAssertFalse(descendants(window).contains { $0 is PageStage },"Old account artwork must clear even when the presentation host cannot dismiss immediately.")
        snapshot(window,name:"Rany-preview-after-owner-change")
    }
    func testMissingCinematicArtworkStillRevealsAndFinishes() async throws {
        var revealed=false,finished=false
        let config=CinematicConfiguration(duration:3.8)
        let root=CinematicIntro(configuration:config,state:nil,stories:[:],destination:nil,imagesOverride:[],onReveal:{revealed=true},onFinish:{finished=true}).environment(\.scenePhase,.active)
        let (window,previous)=show(root)
        defer { window.isHidden=true; previous?.makeKeyAndVisible() }
        for _ in 0..<60 { if finished { break }; try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertTrue(revealed); XCTAssertTrue(finished,"Missing covers must not strand the application.")
        XCTAssertFalse(descendants(window).contains { $0 is PageStage })
    }
    func testReducedMotionCinematicFinishesWithoutPageRenderer() async throws {
        var finishes=0
        let root=CinematicIntro(configuration:CinematicConfiguration(forceReducedMotion:true),state:nil,stories:[:],destination:nil,imagesOverride:[],onReveal:{},onFinish:{finishes+=1}).environment(\.scenePhase,.active)
        let (window,previous)=show(root)
        defer { window.isHidden=true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for:.seconds(1))
        XCTAssertEqual(finishes,1); XCTAssertFalse(descendants(window).contains { $0 is PageStage })
    }
    func testCinematicDoesNotReplayWhenReturningFromBackground() async throws {
        let fixture=CinematicLifecycleFixture(); var finishes=0
        let (window,previous)=show(CinematicLifecycleTestView(fixture:fixture,finish:{finishes+=1}))
        defer { window.isHidden=true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for:.milliseconds(200))
        fixture.phase = .background
        try await Task.sleep(for:.milliseconds(200))
        XCTAssertEqual(finishes,1)
        fixture.phase = .active
        try await Task.sleep(for:.milliseconds(500))
        XCTAssertEqual(finishes,1,"Resuming the same view must not begin another intro.")
    }
    func testCinematicStopsOnAccountSwitchAndCannotFinishTwice() async throws {
        let fixture=CinematicLifecycleFixture(); var finishes=0
        fixture.account=AccountState(user:Account(id:"cinema-owner-a",name:"A",username:"fixture-a"))
        let (window,previous)=show(CinematicLifecycleTestView(fixture:fixture,finish:{finishes+=1}))
        defer { window.isHidden=true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for:.milliseconds(200))
        fixture.account=AccountState(user:Account(id:"cinema-owner-b",name:"B",username:"fixture-b"))
        try await Task.sleep(for:.milliseconds(200))
        XCTAssertEqual(finishes,1)
        fixture.account=nil
        try await Task.sleep(for:.milliseconds(200))
        XCTAssertEqual(finishes,1)
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


@MainActor private final class CinematicLifecycleFixture: ObservableObject {
    @Published var phase: ScenePhase = .active
    @Published var account: AccountState?
}
private struct CinematicLifecycleTestView: View {
    @ObservedObject var fixture: CinematicLifecycleFixture
    var finish: () -> Void
    var body: some View {
        CinematicIntro(configuration:CinematicConfiguration(),state:fixture.account,stories:[:],destination:nil,imagesOverride:[],onReveal:{},onFinish:finish).environment(\.scenePhase,fixture.phase)
    }
}

private struct GoldenProductionLifecycleView: View {
    @ObservedObject var fixture: CinematicLifecycleFixture
    let store: AppStore
    let onStart: (Date) -> Void
    var body: some View {
        RanyExperience(onOpeningStart:onStart)
            .environmentObject(store).environmentObject(store.downloads)
            .environment(\.scenePhase,fixture.phase)
            .environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark)
    }
}
