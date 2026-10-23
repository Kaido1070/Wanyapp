import Foundation

struct APIError: LocalizedError {
    let message: String
    let status: Int
    // Server wording can carry the old name; people only ever see Rany.
    init(message: String,status: Int) { self.message = RanyCopy.visible(message); self.status = status }
    var errorDescription: String? { message }
}
@MainActor final class API {
    static let shared = API()
    private let session: URLSession
    private var credential: String?
    var generation = UUID()
    private let persistCredentials: Bool
    init(configuration: URLSessionConfiguration = .ephemeral, credential: String? = nil, persistCredentials: Bool = true) {
        self.persistCredentials=persistCredentials
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 90
        session = URLSession(configuration: configuration)
        self.credential = credential ?? (persistCredentials ? Keychain.read("session").flatMap { String(data:$0, encoding:.utf8) } : nil)
    }
    func clear() { generation = UUID(); credential = nil; if persistCredentials { Keychain.delete("session") } }
    func request(_ path: String, query: [String:String] = [:], method: String = "GET", body: Data? = nil,contentType: String = "application/json") throws -> URLRequest {
        guard path.hasPrefix("/api/"), !path.contains("://"), !path.contains("?"), !path.contains("#") else { throw APIError(message:"عنوان غير صالح",status:0) }
        guard let target=URL(string:path,relativeTo:website)?.absoluteURL, target.host == website.host,
              var components=URLComponents(url:target,resolvingAgainstBaseURL:false) else { throw APIError(message:"عنوان غير صالح",status:0) }
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name:$0.key,value:$0.value) } }
        var req = URLRequest(url:components.url!); req.httpMethod = method; req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField:"Accept")
        req.setValue(website.absoluteString, forHTTPHeaderField:"Origin")
        if body != nil { req.setValue(contentType, forHTTPHeaderField:"Content-Type") }
        if let credential { req.setValue("anytime_session=" + credential, forHTTPHeaderField:"Cookie") }
        return req
    }
    func raw(_ path: String, query: [String:String] = [:], method: String = "GET", body: Data? = nil,contentType: String = "application/json") async throws -> Data {
        let scope = generation
        let (data, response) = try await session.data(for: request(path,query:query,method:method,body:body,contentType:contentType))
        guard scope == generation else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw APIError(message:"تعذر الاتصال",status:0) }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { NotificationCenter.default.post(name:.ranySessionExpired,object:nil) }
            let value = try? JSONDecoder().decode(JSONValue.self,from:data)
            throw APIError(message:value?["message"].string.isEmpty == false ? value!["message"].string : "تعذر إكمال الطلب (\(http.statusCode))",status:http.statusCode)
        }
        if path == "/api/login" || path == "/api/change-password" {
            let fields = http.allHeaderFields.reduce(into:[String:String]()) { if let k = $1.key as? String, let v = $1.value as? String { $0[k] = v } }
            guard let cookie = HTTPCookie.cookies(withResponseHeaderFields:fields,for:website).first(where:{$0.name == "anytime_session"}) else { throw APIError(message:"لم تُحفظ جلسة الدخول؛ أعد تسجيل الدخول",status:path == "/api/change-password" ? 401 : 0) }
            if persistCredentials {
                do { try Keychain.save(Data(cookie.value.utf8),key:"session") }
                catch { credential=nil; Keychain.delete("session"); throw APIError(message:"تعذر حفظ الجلسة الآمنة؛ سجل الدخول مجددًا",status:401) }
            }
            credential = cookie.value
            if path == "/api/change-password" { generation=UUID() }
        }
        return data
    }
    func get<T: Decodable>(_ path: String, query: [String:String] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await raw(path,query:query)
        return try await API.decode(T.self,from:data)
    }
    // A nonisolated async function runs on the global executor, so large
    // responses (chapter archives, feeds) are decoded off the main thread.
    nonisolated private static func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        try JSONDecoder().decode(T.self,from:data)
    }
    func send<T: Encodable>(_ path: String, method: String = "POST", value: T) async throws {
        _ = try await raw(path,method:method,body:JSONEncoder().encode(value))
    }
    // Saved payloads and caches may hold absolute URLs on our own current or old
    // host; reduce them to a path so they are requested on the current origin.
    static func ownPath(_ url: String) -> String {
        guard let components = URLComponents(string:url), let host = components.host?.lowercased(),
              host == website.host || legacyWebsiteHosts.contains(host), components.path.hasPrefix("/api/") else { return url }
        return components.path + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
    }
    func imageRequest(source: String, url rawURL: String, referer: String? = nil, quality: ImageQuality? = nil) throws -> URLRequest {
        let url = API.ownPath(rawURL)
        if url.hasPrefix("/api/work-snapshots/cover") || url.hasPrefix("/api/source/image") {
            let components = URLComponents(string:url)!
            var q: [String:String] = [:]; components.queryItems?.forEach { q[$0.name] = $0.value }
            if components.path == "/api/source/image", let quality { q["quality"]=quality.rawValue }
            var r = try request(components.path,query:q); r.setValue("image/*",forHTTPHeaderField:"Accept"); return r
        }
        let original = source == "teamx" ? url.replacingOccurrences(of:"thumbnail_",with:"") : url
        var query = ["source":source,"url":original]; query["referer"] = referer; query["quality"] = quality?.rawValue
        var req = try request("/api/source/image",query:query)
        req.setValue("image/*",forHTTPHeaderField:"Accept"); return req
    }
    // Mirrors the website: the series response is the chapter list. Extra pages
    // only add chapters, a failed page never hides the ones already known, and
    // every chapter the site can open is kept, including number-only entries
    // (the reader opens those by number, exactly like the site).
    func fullSeries(_ key: String) async throws -> Story {
        var story = try await getRetrying("/api/source/series",query:["key":key],as:SeriesResponse.self).item
        var byNumber = Dictionary((story.chapters ?? []).map { ($0.id,$0) },uniquingKeysWith:SeriesChapters.prefer)
        if story.chapterListComplete == false || (story.chapterPageCount ?? 1) > 1 {
            let pages = await chapterPages(key,declared:max(1,story.chapterPageCount ?? 1))
            for c in pages.chapters { byNumber[c.id] = byNumber[c.id].map { SeriesChapters.prefer($0,c) } ?? c }
            story.chapterListComplete = pages.complete && ((story.chapterPageCount ?? 1) > 1 || pages.added)
        }
        let chapters = byNumber.values.sorted { $0.number < $1.number }
        if chapters.isEmpty {
            if story.sourceTemporarilyUnavailable == true { throw APIError(message:"المصدر متعثر الآن، أعد المحاولة لاحقًا",status:503) }
            throw APIError(message:"لم يرجع المصدر أي فصل لهذه القصة بعد",status:0)
        }
        story.chapters = chapters
        if let declared = story.declaredChapterCount, declared > chapters.count { story.chapterListComplete = false }
        else if story.chapterListComplete == nil { story.chapterListComplete = true }
        return story
    }
    // Pages are fetched one by one, each retried; the walk stops at the first page
    // that still fails and reports what it gathered instead of throwing it away.
    private func chapterPages(_ key: String,declared: Int) async -> (chapters: [Chapter],complete: Bool,added: Bool) {
        var collected: [Chapter] = []
        var page = 1, pages = declared
        while page <= min(pages,2000) {
            if Task.isCancelled { return (collected,false,!collected.isEmpty) }
            guard let result = try? await getRetrying("/api/source/chapters-page",query:["key":key,"page":String(page)],as:ChaptersResponse.self) else {
                return (collected,false,!collected.isEmpty)
            }
            collected += result.chapters
            pages = max(pages,result.pages)
            if result.chapters.isEmpty && page >= result.pages { break }
            page += 1
        }
        return (collected,true,!collected.isEmpty)
    }
    // Source scrapers occasionally time out once; the website retries twice too.
    func getRetrying<T: Decodable>(_ path: String,query: [String:String],as type: T.Type,attempts: Int = 3) async throws -> T {
        var failure: Error = APIError(message:"تعذر الاتصال",status:0)
        for attempt in 0..<attempts {
            do { return try await get(path,query:query,as:type) }
            catch {
                if isRequestCancellation(error) { throw error }
                if let api = error as? APIError, (400..<500).contains(api.status), api.status != 408, api.status != 429 { throw error }
                failure = error
                if attempt < attempts-1 { try await Task.sleep(nanoseconds:UInt64(attempt+1)*600_000_000) }
            }
        }
        throw failure
    }
    func chapter(_ key: String, _ chapter: Chapter) async throws -> ChapterPayload {
        var q = ["key":key,"number":chapterNumber(chapter.number)]; q["chapterUrl"] = chapter.url
        let result = try await getRetrying("/api/source/chapter",query:q,as:ChapterResponse.self).chapter
        guard result.item.key == key, result.number == chapter.number, !result.pages.isEmpty else { throw APIError(message:"بيانات الفصل غير مكتملة",status:0) }
        return result
    }
}

extension Notification.Name { static let ranySessionExpired = Notification.Name("rany.session.expired") }

extension API {
    func getMutation<T: Encodable>(_ path: String,value: T,method: String = "POST") async throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self,from:await raw(path,method:method,body:JSONEncoder().encode(value)))
    }
}
