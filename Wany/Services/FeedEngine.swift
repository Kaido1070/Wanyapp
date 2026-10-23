import Foundation
import JavaScriptCore

// The shared website algorithms run in JavaScriptCore on a dedicated serial queue.
// Only network requests (API) and progress delivery hop to the main actor.
final class FeedEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label:"Rany.FeedEngine",qos:.userInitiated)
    private let scope: UUID
    // Everything below is touched on `queue` only.
    private var context: JSContext?
    private var completions: [String: CheckedContinuation<Data,Error>] = [:]
    private var callbacks: [String: @MainActor (String)->Void] = [:]
    @MainActor init() {
        scope = API.shared.generation
        let source = Bundle.main.url(forResource:"FeedEngine",withExtension:"js").flatMap { try? String(contentsOf:$0) }
        queue.async { self.setUp(source:source) }
    }
    private func settle(_ id: String, _ text: String, _ error: String) {
        context?.objectForKeyedSubscript("settleRequest").call(withArguments:[id,text,error])
    }
    private func setUp(source: String?) {
        guard let context = JSContext() else { return }
        self.context = context
        let scope = self.scope
        let request: @convention(block) (String,String,String,String) -> Void = { [weak self] id,path,method,body in
            Task { @MainActor in
                guard let self else { return }
                do {
                    guard scope == API.shared.generation else { throw CancellationError() }
                    guard let components = URLComponents(string:path), components.path.hasPrefix("/api/") else { throw APIError(message:"طلب غير صالح",status:0) }
                    var q: [String:String] = [:]; components.queryItems?.forEach { q[$0.name] = $0.value }
                    let data = try await API.shared.raw(components.path,query:q,method:method,body:body == "null" ? nil : Data(body.utf8))
                    guard scope == API.shared.generation else { throw CancellationError() }
                    self.queue.async { self.settle(id,String(decoding:data,as:UTF8.self),"") }
                } catch {
                    let message = error.localizedDescription
                    self.queue.async { self.settle(id,"",message) }
                }
            }
        }
        let progress: @convention(block) (String,String) -> Void = { [weak self] id,progress in
            guard let callback = self?.callbacks[id] else { return }
            Task { @MainActor in callback(progress) }
        }
        let result: @convention(block) (String,String,String) -> Void = { [weak self] id,text,error in
            guard let self, let continuation = self.completions.removeValue(forKey:id) else { return }
            self.callbacks.removeValue(forKey:id)
            if error.isEmpty { continuation.resume(returning:Data(text.utf8)) } else { continuation.resume(throwing:APIError(message:error,status:0)) }
        }
        let timer: @convention(block) (String,Double) -> Void = { [weak self] id,delay in
            self?.queue.asyncAfter(deadline:.now()+max(0,delay)/1000) { [weak self] in self?.context?.objectForKeyedSubscript("fireTimer").call(withArguments:[id]) }
        }
        context.setObject(request,forKeyedSubscript:"nativeRequest" as NSString)
        context.setObject(progress,forKeyedSubscript:"nativeProgress" as NSString)
        context.setObject(result,forKeyedSubscript:"nativeResult" as NSString)
        context.setObject(timer,forKeyedSubscript:"nativeTimer" as NSString)
        if let source { context.evaluateScript(source) }
    }
    @MainActor func run(_ kind: String, data: AccountData, user: String, page: Int = 1, progress: @escaping @MainActor (String)->Void) async throws -> Data {
        guard scope == API.shared.generation else { throw CancellationError() }
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let context = self.context else { continuation.resume(throwing:APIError(message:"تعذر تجهيز الصفحة",status:0)); return }
                do {
                    let input = try JSONSerialization.jsonObject(with:JSONEncoder().encode(data))
                    self.completions[id] = continuation; self.callbacks[id] = progress
                    context.exception = nil
                    context.objectForKeyedSubscript("runFeed").call(withArguments:[kind,input,user,page,id])
                    if let error = context.exception {
                        self.callbacks.removeValue(forKey:id)
                        self.completions.removeValue(forKey:id)?.resume(throwing:APIError(message:error.toString() ?? "تعذر تجهيز الصفحة",status:0))
                    }
                } catch { continuation.resume(throwing:error) }
            }
        }
    }
}
