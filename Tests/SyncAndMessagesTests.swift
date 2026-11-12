import XCTest
@testable import Wany

// Changes-only account reads, messages and the image limit notice.
@MainActor final class SyncAndMessagesTests: XCTestCase {
    private func record(_ chapter: Double, _ at: Double) -> ProgressRecord {
        ProgressRecord(mangaId:"tx:a",chapter:chapter,percent:100,updatedAt:at)
    }

    func testChangesCompleteTheHeldCopy() {
        var held = AccountData()
        held.progress = ["tx:a:1":record(1,1),"tx:a:2":record(2,1)]
        held.completed = ["tx:a:1","tx:a:2"]
        held.favorites = ["old"]
        var changes = AccountData()
        changes.progress = ["tx:a:2":record(2,9),"tx:a:3":record(3,9)]
        changes.completed = ["tx:a:2","tx:a:3"]
        changes.favorites = ["new"]
        let merged = held.applyingChanges(changes)
        XCTAssertEqual(Set(merged.progress.keys),["tx:a:1","tx:a:2","tx:a:3"])
        XCTAssertEqual(merged.progress["tx:a:2"]?.updatedAt,9,"the server's newer row replaces the held one")
        XCTAssertEqual(merged.completed,["tx:a:1","tx:a:2","tx:a:3"],"completions are added once, in order")
        XCTAssertTrue(merged.isCompleted("tx:a:3"))
        XCTAssertEqual(merged.favorites,["new"],"favorites always arrive complete")
    }

    func testAccountAnswersDecodeWithAndWithoutTheNewFields() throws {
        let data = #"{"version":3,"favorites":[],"library":[],"progress":{},"completed":[],"lastOpened":null}"#
        let old = try JSONDecoder().decode(DataResponse.self,from:Data(#"{"data":\#(data)}"#.utf8))
        XCTAssertNil(old.syncedAt); XCTAssertNil(old.delta); XCTAssertNil(old.unreadMessages)
        let new = try JSONDecoder().decode(DataResponse.self,from:Data(#"{"data":\#(data),"syncedAt":1700000000000,"delta":true,"unreadMessages":3}"#.utf8))
        XCTAssertEqual(new.syncedAt,1_700_000_000_000); XCTAssertEqual(new.delta,true); XCTAssertEqual(new.unreadMessages,3)
    }

    func testSavedAccountsWithoutSyncMarksStillLoad() throws {
        let state = AccountState(user:Account(id:"u",name:"U",username:"u"))
        var json = try JSONSerialization.jsonObject(with:JSONEncoder().encode(state)) as! [String:Any]
        json.removeValue(forKey:"dataSyncedAt"); json.removeValue(forKey:"dataFullAt")
        let decoded = try JSONDecoder().decode(AccountState.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertNil(decoded.dataSyncedAt); XCTAssertNil(decoded.dataFullAt)
    }

    func testMessagesParseTextAndSharedChapters() throws {
        let value = try JSONDecoder().decode(JSONValue.self,from:Data(#"{"id":7,"mine":true,"body":"اقرأها","mangaId":"az:overgeared-12","chapter":933,"createdAt":1700000000000}"#.utf8))
        let message = ChatMessage(value)
        XCTAssertEqual(message.id,7); XCTAssertTrue(message.mine); XCTAssertEqual(message.body,"اقرأها")
        XCTAssertEqual(message.mangaId,"az:overgeared-12"); XCTAssertEqual(message.chapter,933)
        let plain = ChatMessage(try JSONDecoder().decode(JSONValue.self,from:Data(#"{"id":8,"mine":false,"body":"هلا","mangaId":null,"chapter":null,"createdAt":1}"#.utf8)))
        XCTAssertNil(plain.mangaId); XCTAssertNil(plain.chapter)
    }

    func testRepliesParseWithTheirPreview() throws {
        let reply = ChatMessage(try JSONDecoder().decode(JSONValue.self,from:Data(#"{"id":9,"mine":false,"body":"ايه","mangaId":null,"chapter":null,"createdAt":2,"replyTo":{"id":7,"mine":true,"body":"شفت الفصل؟","mangaId":"tx:a"}}"#.utf8)))
        XCTAssertEqual(reply.replyTo?.id,7); XCTAssertEqual(reply.replyTo?.mine,true); XCTAssertEqual(reply.replyTo?.body,"شفت الفصل؟")
        XCTAssertEqual(reply.replyTo?.mangaId,"tx:a"); XCTAssertEqual(reply.replyTo?.deleted,false)
        let gone = ChatMessage(try JSONDecoder().decode(JSONValue.self,from:Data(#"{"id":10,"mine":true,"body":"x","createdAt":3,"replyTo":{"id":8,"deleted":true}}"#.utf8)))
        XCTAssertEqual(gone.replyTo?.deleted,true); XCTAssertEqual(gone.replyTo?.body,"")
        let plain = ChatMessage(try JSONDecoder().decode(JSONValue.self,from:Data(#"{"id":11,"mine":true,"body":"y","createdAt":4,"replyTo":null}"#.utf8)))
        XCTAssertNil(plain.replyTo)
    }

    func testEmojiOnlyMessagesShowLarge() {
        for text in ["🔥","🔥🔥"," 😂😂😂 ","👍🏽","❤️","👨‍👩‍👧"] { XCTAssertTrue(isEmojiOnly(text),text) }
        for text in ["","1","تمام 🔥","🔥🔥🔥🔥","hi","#"] { XCTAssertFalse(isEmojiOnly(text),text) }
    }

    func testImageLimitIsSaidOnceAMonth() {
        let downloads = Downloads.shared
        let previous = UserDefaults.standard.string(forKey:"rany.imageLimitNotice")
        defer { UserDefaults.standard.set(previous,forKey:"rany.imageLimitNotice"); downloads.notice = nil }
        UserDefaults.standard.removeObject(forKey:"rany.imageLimitNotice")
        let november = Date(timeIntervalSince1970:1_794_000_000)
        downloads.notice = nil; downloads.noteImageLimit(now:november)
        XCTAssertNotNil(downloads.notice)
        downloads.notice = nil; downloads.noteImageLimit(now:november.addingTimeInterval(3600))
        XCTAssertNil(downloads.notice,"not again in the same month")
        downloads.noteImageLimit(now:november.addingTimeInterval(40*86400))
        XCTAssertNotNil(downloads.notice,"said again the next month")
        XCTAssertFalse(downloads.notice!.contains("Wany"))
    }
}
