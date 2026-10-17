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
    func testCircuitMovesRightUpAndLeftDownWithoutDuplicatingSlots() {
        let right = RanyBackdropMotion.position(index:3,elapsed:0,height:800)
        let left = RanyBackdropMotion.position(index:10,elapsed:0,height:800)
        XCTAssertEqual(right.x,0.77,accuracy:0.001)
        XCTAssertEqual(left.x,0.23,accuracy:0.001)
        XCTAssertLessThan(RanyBackdropMotion.position(index:3,elapsed:10,height:800).y,right.y)
        XCTAssertGreaterThan(RanyBackdropMotion.position(index:10,elapsed:10,height:800).y,left.y)
        for second in stride(from:0,through:1800,by:5) {
            let points = (0..<14).map { RanyBackdropMotion.position(index:$0,elapsed:Double(second),height:800) }
            XCTAssertEqual(Set(points.map { String(format:"%.5f,%.5f",Double($0.x),Double($0.y)) }).count,14)
        }
    }
    @MainActor func testFallbackCoversHaveDistinctVisualSignatures() {
        let hashes = (1...14).compactMap { UIImage(named:"RanyDefault\($0)")?.cgImage }.compactMap { RanyCoverQuality.signature($0) }
        XCTAssertEqual(hashes.count,14)
        for i in hashes.indices { for j in hashes.indices where j > i { XCTAssertFalse(RanyCoverQuality.matches(hashes[i],hashes[j])) } }
    }
    private func story(_ key: String, cover: String = "https://example.invalid/cover.jpg") -> Story {
        Story(key:key,source:"teamx",slug:key,type:"manhwa",url:"https://example.invalid/"+key,title:key,cover:cover,genres:[])
    }
}
