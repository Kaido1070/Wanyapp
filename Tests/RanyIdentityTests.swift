import XCTest
import UIKit
@testable import Wany

final class RanyIdentityTests: XCTestCase {
    func testAbbreviationKeepsTheActualLettersFromThePhrase() {
        XCTAssertEqual(String(RanyIdentity.retainedIndices.map { RanyIdentity.letters[$0] }),"RANY")
        XCTAssertEqual(RanyIdentity.retainedIndices.first,0)
        XCTAssertEqual(String(RanyIdentity.retainedIndices.map { RanyIdentity.displayLetters[$0] }),"𝓡𝓐𝓝𝓨")
        XCTAssertEqual(RanyIdentity.displayMark,"𝓡")
    }
    func testArtworkPlanSkipsMissingCoversAndPreservesReadingPriority() {
        let reading = LibraryEntry(mangaId:"reading",status:"reading",addedAt:1,updatedAt:10)
        let dropped = LibraryEntry(mangaId:"dropped",status:"dropped",addedAt:1,updatedAt:20)
        let blank = LibraryEntry(mangaId:"blank",status:"reading",addedAt:1,updatedAt:30)
        var data = AccountData(); data.library = [dropped,blank,reading]; data.favorites = ["reading","favorite"]
        let stories = ["reading":story("reading"),"dropped":story("dropped"),"blank":story("blank",cover:"  "),"favorite":story("favorite")]
        XCTAssertEqual(RanyBackdropPlan.candidates(data:data,stories:stories).map(\.key),["reading","favorite"])
        XCTAssertTrue(RanyBackdropPlan.candidates(data:AccountData(),stories:stories).isEmpty)
    }
    func testCandidatePlanIsDeterministicAndBoundsDecodeWork() {
        var data = AccountData()
        data.library = (0..<80).map { LibraryEntry(mangaId:String($0),status:"reading",addedAt:1,updatedAt:100) }
        let stories = Dictionary(uniqueKeysWithValues:(0..<80).map { (String($0),story(String($0))) })
        let a = RanyBackdropPlan.candidates(data:data,stories:stories)
        data.library.reverse()
        XCTAssertEqual(a,RanyBackdropPlan.candidates(data:data,stories:stories))
        XCTAssertEqual(a.count,RanyIdentity.maxBackdropCandidates)
        XCTAssertEqual(RanyIdentity.maxBackdropCovers,14)
    }
    @MainActor func testEmbeddedFontAndDefaultCoversAreAvailableOffline() {
        RanyTypography.registerFont()
        XCTAssertNotNil(UIFont(name:RanyIdentity.fontName,size:54))
        for index in 1...14 {
            let image = UIImage(named:"RanyDefault\(index)")
            XCTAssertNotNil(image)
            XCTAssertLessThanOrEqual(image?.cgImage?.width ?? .max,320)
            XCTAssertLessThanOrEqual(image?.cgImage?.height ?? .max,400)
        }
        XCTAssertNotNil(UIImage(named:"Logo"))
        XCTAssertNotNil(UIImage(named:"RanyMonogram"))
    }
    func testAmbienceRejectsSmallLandscapeAndLowDetailCovers() {
        XCTAssertFalse(RanyCoverQuality.acceptsDimensions(width:160,height:220))
        XCTAssertFalse(RanyCoverQuality.acceptsDimensions(width:1200,height:600))
        XCTAssertTrue(RanyCoverQuality.acceptsDimensions(width:512,height:724))
        XCTAssertFalse(RanyCoverQuality.acceptsDimensions(width:320,height:440),"Covers smaller than the staged wallpaper size would be enlarged and look soft.")
        let flat = UIGraphicsImageRenderer(size:CGSize(width:100,height:140)).image { context in
            UIColor.gray.setFill(); context.fill(CGRect(x:0,y:0,width:100,height:140))
        }
        XCTAssertFalse(RanyCoverQuality.hasDetail(flat.cgImage!))
    }
    func testSameTitleAcrossSourcesOnlyUsesOneArtworkCandidate() {
        var data = AccountData()
        data.favorites = ["sourceA","sourceB"]
        var a = story("sourceA"), b = story("sourceB")
        a.title = "Solo Leveling"; b.title = "solo-leveling"
        XCTAssertEqual(RanyBackdropPlan.candidates(data:data,stories:[a.key:a,b.key:b]).count,1)
    }
    func testQuietLibraryHasFourteenStableSlotsWithBoundedMotion() {
        let initial = (0..<14).map { RanyBackdropMotion.position(index:$0,elapsed:0,height:800) }
        XCTAssertGreaterThan(Set(initial.map { Int($0.x*10) }).count,5)
        var changed = false
        for second in stride(from:1,through:180,by:3) {
            let points = (0..<14).map { RanyBackdropMotion.position(index:$0,elapsed:Double(second),height:800) }
            XCTAssertEqual(Set(points.map { "\($0.x),\($0.y)" }).count,14)
            for i in points.indices {
                XCTAssertLessThan(abs(points[i].x-initial[i].x),0.045)
                XCTAssertLessThan(abs(points[i].y-initial[i].y),0.026)
                changed = changed || points[i] != initial[i]
            }
        }
        XCTAssertTrue(changed)
    }
    func testProgressDoesNotClaimSyncWithoutServerConfirmation() {
        XCTAssertEqual(RanyProgressState.resolve(locallySaved:true,confirmed:false,pending:false,syncing:false,sessionValid:true),.local)
        XCTAssertEqual(RanyProgressState.resolve(locallySaved:true,confirmed:true,pending:true,syncing:false,sessionValid:true),.local)
        XCTAssertEqual(RanyProgressState.resolve(locallySaved:true,confirmed:true,pending:false,syncing:false,sessionValid:false),.local)
        XCTAssertEqual(RanyProgressState.resolve(locallySaved:true,confirmed:false,pending:true,syncing:true,sessionValid:true),.syncing)
        XCTAssertEqual(RanyProgressState.resolve(locallySaved:false,confirmed:true,pending:false,syncing:false,sessionValid:true),.saveFailed)
        XCTAssertEqual(RanyProgressState.resolve(locallySaved:true,confirmed:true,pending:false,syncing:false,sessionValid:true),.synchronized)
    }
    @MainActor func testFallbackCoversHaveDistinctVisualSignatures() {
        let hashes = (1...14).compactMap { UIImage(named:"RanyDefault\($0)")?.cgImage }.compactMap { RanyCoverQuality.signature($0) }
        XCTAssertEqual(hashes.count,14)
        for i in hashes.indices { for j in hashes.indices where j > i { XCTAssertFalse(RanyCoverQuality.matches(hashes[i],hashes[j])) } }
    }
    func testIntroUsesMeasuredRightHandDestinationWithSafeAreaOffset() {
        let frame = CGRect(x:330,y:66,width:32,height:32)
        let layout = RanyIntroLayout(size:CGSize(width:390,height:800),origin:CGPoint(x:0,y:47),destinationFrame:frame,sourceFrame:CGRect(x:149,y:100,width:92,height:92))
        let destination = layout.point(index:0,stage:4,login:false)
        XCTAssertEqual(destination,CGPoint(x:346,y:35))
        XCTAssertGreaterThan(destination.x,195)
        XCTAssertEqual(layout.destinationSize(login:false),32)
        XCTAssertEqual(layout.loginPoint,CGPoint(x:195,y:99))
    }
    func testAllFourteenCoversStartAsADistinctCentralCluster() {
        let points = (0..<14).map { RanyBackdropMotion.scatteredPosition(index:$0) }
        XCTAssertEqual(Set(points.map { "\($0.x),\($0.y)" }).count,14)
        for point in points {
            XCTAssertTrue((0.35...0.65).contains(Double(point.x)))
            XCTAssertTrue((0.33...0.59).contains(Double(point.y)))
        }
    }
    private func story(_ key: String, cover: String = "https://example.invalid/cover.jpg") -> Story {
        Story(key:key,source:"teamx",slug:key,type:"manhwa",url:"https://example.invalid/"+key,title:key,cover:cover,genres:[])
    }
    func testVisibleTextNeverShowsTheOldNameOrTheWebsite() {
        let releases=AppVersion.releases.flatMap(\.changes).map(RanyCopy.visible)
        XCTAssertFalse(releases.isEmpty)
        let trophies=ReadingMilestones.groups.flatMap(\.milestones).flatMap { [$0.label,$0.description] }
        for text in releases+trophies {
            XCTAssertFalse(text.contains("Wany"),text); XCTAssertFalse(text.contains("الموقع"),text); XCTAssertFalse(text.contains("للموقع"),text)
        }
        XCTAssertEqual(APIError(message:"Wany لن يعتبر القائمة كاملة",status:0).message,"Rany لن يعتبر القائمة كاملة")
    }
}
