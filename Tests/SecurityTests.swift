import XCTest
@testable import Wany

final class APIStubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int,[String:String],Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status,headers,data)=try Self.handler!(request)
            let response=HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:headers)!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
@MainActor final class SecurityTests: XCTestCase {
    private func client() -> API {
        let config=URLSessionConfiguration.ephemeral; config.protocolClasses=[APIStubProtocol.self]
        return API(configuration:config,credential:"fixture-old",persistCredentials:false)
    }
    func testPasswordChangeStoresRotatedSessionBeforeFollowingRequest() async throws {
        let api=client()
        APIStubProtocol.handler={ request in
            XCTAssertEqual(request.httpMethod,"POST")
            XCTAssertEqual(request.value(forHTTPHeaderField:"Cookie"),"anytime_session=fixture-old")
            return (200,["Set-Cookie":"anytime_session=fixture-rotated; Path=/; HttpOnly; Secure; SameSite=Lax"],Data("{\"ok\":true}".utf8))
        }
        try await api.send("/api/change-password",value:["currentPassword":"fixture-current","newPassword":"fixture-replacement"])
        XCTAssertEqual(try api.request("/api/data").value(forHTTPHeaderField:"Cookie"),"anytime_session=fixture-rotated")
        api.clear()
        XCTAssertNil(try api.request("/api/data").value(forHTTPHeaderField:"Cookie"))
    }
    func testFailedChangeDoesNotReplaceSessionAndPropagatesExpiredStatus() async {
        let api=client()
        APIStubProtocol.handler={ _ in (401,[:],Data("{\"message\":\"expired\"}".utf8)) }
        do { try await api.send("/api/security-question",value:["currentPassword":"fixture"]); XCTFail("Expired sessions must fail") }
        catch { XCTAssertEqual((error as? APIError)?.status,401) }
        XCTAssertEqual(try? api.request("/api/data").value(forHTTPHeaderField:"Cookie"),"anytime_session=fixture-old")
    }
    func testRecoveryQuestionAndFinalVerificationUseServerContract() async throws {
        let api=client()
        APIStubProtocol.handler={ request in
            XCTAssertEqual(request.url?.path,"/api/recover-password")
            return (200,[:],Data("{\"question\":\"fixture question\"}".utf8))
        }
        let result=try await api.getMutation("/api/recover-password",value:["action":"question","username":"fixture"])
        XCTAssertEqual(result["question"].string,"fixture question")
        XCTAssertFalse(SecurityInput.validPassword("short",confirmation:"short"))
        XCTAssertFalse(SecurityInput.validPassword("long-enough",confirmation:"mismatch"))
        XCTAssertTrue(SecurityInput.validPassword("long-enough",confirmation:"long-enough"))
    }
}
