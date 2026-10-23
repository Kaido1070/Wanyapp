import Foundation

struct APIError: LocalizedError {
    let message: String
    let status: Int
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
    func imageRequest(source: String, url: String, referer: String? = nil, quality: ImageQuality? = nil) throws -> URLRequest {
        if url.hasPrefix("/api/work-snapshots/cover") {
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
    func fullSeries(_ key: String) async throws -> Story {
        var story = try await get("/api/source/series",query:["key":key],as:SeriesResponse.self).item
        if story.sourceTemporarilyUnavailable == true { throw APIError(message:"المصدر متعثر الآن، أعد المحاولة لاحقًا",status:503) }
        var byNumber = Dictionary((story.chapters ?? []).map { ($0.id,$0) },uniquingKeysWith: { a,b in a.url == nil ? b : a })
        if story.chapterListComplete == false || (story.chapterPageCount ?? 1) > 1 {
            var page = 1
            var pages = max(1,story.chapterPageCount ?? 1)
            while page <= pages {
                try Task.checkCancellation()
                let result = try await get("/api/source/chapters-page",query:["key":key,"page":String(page)],as:ChaptersResponse.self)
                guard result.page == page else { throw APIError(message:"المصدر أعاد صفحة فصول غير متوقعة",status:0) }
                pages = max(pages,result.pages)
                guard pages < 10000 else { throw APIError(message:"قائمة الفصول غير صالحة",status:0) }
                for c in result.chapters { byNumber[c.id] = c }
                page += 1
            }
        }
        let real = byNumber.values.filter { $0.synthetic != true }.sorted { $0.number < $1.number }
        guard !real.isEmpty else { throw APIError(message:"لم يرجع المصدر فصولًا قابلة للتحميل",status:0) }
        if let declared = story.declaredChapterCount, declared > real.count {
            throw APIError(message:"القائمة ناقصة: \(real.count) من \(declared) فصل. أعد المحاولة حتى تكتمل القائمة.",status:0)
        }
        story.chapters = real; story.chapterListComplete = true; return story
    }
    func chapter(_ key: String, _ chapter: Chapter) async throws -> ChapterPayload {
        var q = ["key":key,"number":chapterNumber(chapter.number)]; q["chapterUrl"] = chapter.url
        let result = try await get("/api/source/chapter",query:q,as:ChapterResponse.self).chapter
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
