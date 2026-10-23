import XCTest
@testable import Wany

@MainActor final class CollectionTests: XCTestCase {
    func testCachedPageClearsPreviousAccountAndLogoutOffline() async {
        let store=AppStore(startServices:false); store.online=false
        let page=CachedPage()
        store.state=AccountState(user:Account(id:"privacy-fixture-a",name:"A",username:"fixture-a"))
        await page.load("/api/profiles/fixture",store:store)
        page.value = .object(["private":.string("account-a")]); page.loading=true
        store.state=AccountState(user:Account(id:"privacy-fixture-b",name:"B",username:"fixture-b"))
        await page.load("/api/profiles/fixture",store:store)
        XCTAssertEqual(page.value["private"].string,""); XCTAssertFalse(page.loading)
        page.value = .object(["private":.string("account-b")])
        store.state=nil
        await page.load("/api/profiles/fixture",store:store)
        XCTAssertEqual(page.value["private"].string,"")
    }
    func testManagedOrderingPreservesUnrelatedSectionsAndVisibility() throws {
        let all=[RanyProfileSection(key:"reading",sectionType:"continue_reading",position:1,isVisible:true),RanyProfileSection(key:"favorite",sectionType:"favorites",position:2,isVisible:false),RanyProfileSection(key:"activity",sectionType:"my_activity",position:3,isVisible:true),RanyProfileSection(key:"custom",sectionType:"custom_list",referenceId:"fixture-list",position:4,isVisible:true)]
        let reordered=SectionOrder.replacingManaged(all,with:[all[3],all[1]])
        XCTAssertEqual(reordered.map(\.key),["reading","custom","activity","favorite"])
        XCTAssertFalse(reordered[3].isVisible)
        struct Payload: Encodable { let sections: [ProfileSectionInput] }
        let json=try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(Payload(sections:reordered.map(\.payload))))
        XCTAssertEqual(json["sections"].array[1]["referenceId"].string,"fixture-list")
        XCTAssertEqual(json["sections"].array[3]["isVisible"].boolean,false)
    }
    func testListItemMoveRetainsIdentityAndRejectsOutOfBounds() {
        XCTAssertEqual(SectionOrder.moving(["a","b","c"],from:0,to:2),["b","c","a"])
        XCTAssertEqual(SectionOrder.moving(["a","b"],from:0,to:-1),["a","b"])
        XCTAssertEqual(apiComponent("tx:work/name?x=1"),"tx%3Awork%2Fname%3Fx%3D1")
    }
    func testListFieldsMatchBackendLimitsAndRelationshipStates() {
        XCTAssertFalse(ListEditorInput(name:"",description:"",iconKey:"book").valid)
        XCTAssertFalse(ListEditorInput(name:"fixture",description:String(repeating:"a",count:501),iconKey:"book").valid)
        XCTAssertTrue(ListEditorInput(name:"fixture",description:"description",iconKey:"dragon").valid)
        XCTAssertEqual(FriendRelation.allCases.count,4)
    }
    func testSectionsDecodeServerShapesAndJoinLists() throws {
        let sections=Data(#"{"sections":[{"key":"fav","sectionType":"favorites","referenceId":null,"position":"2","isVisible":true,"previewItems":[]},{"key":"l1","sectionType":"custom_list","referenceId":"list-1","position":1,"isVisible":false},{"key":"gone","sectionType":"custom_list","referenceId":"list-x","position":3,"isVisible":true}]}"#.utf8)
        let lists=Data(#"{"lists":[{"id":"list-1","name":"مختارات","description":null,"iconKey":null,"itemCount":4}]}"#.utf8)
        let decoded=try JSONDecoder().decode(SectionsResponse.self,from:sections)
        let decodedLists=try JSONDecoder().decode(ListsResponse.self,from:lists).lists
        let joined=SectionOrder.joining(decoded.sections,lists:decodedLists)
        XCTAssertEqual(joined.map(\.key),["l1","fav"])
        XCTAssertEqual(joined[0].title,"مختارات"); XCTAssertEqual(joined[0].list?.iconKey,"lists"); XCTAssertEqual(joined[0].list?.itemCount,4)
        XCTAssertFalse(joined[0].isVisible)
    }
}
