import Foundation
import JavaScriptCore

@MainActor final class FeedEngine {
    private let context: JSContext
    private let scope: UUID
    private var completions: [String: CheckedContinuation<Data,Error>] = [:]
    private var callbacks: [String: (String)->Void] = [:]
    init() {
        context = JSContext()!; scope = API.shared.generation
        let request: @convention(block) (String,String,String,String) -> Void = { [weak self] id,path,method,body in
            Task { @MainActor in
                guard let self else { return }
                do {
                    guard self.scope == API.shared.generation else { throw CancellationError() }
                    guard let components = URLComponents(string:path), components.path.hasPrefix("/api/") else { throw APIError(message:"طلب غير صالح",status:0) }
                    var q: [String:String] = [:]; components.queryItems?.forEach { q[$0.name] = $0.value }
                    let data = try await API.shared.raw(components.path,query:q,method:method,body:body == "null" ? nil : Data(body.utf8))
                    guard self.scope == API.shared.generation else { throw CancellationError() }
                    self.context.objectForKeyedSubscript("settleRequest").call(withArguments:[id,String(decoding:data,as:UTF8.self),""])
                } catch { self.context.objectForKeyedSubscript("settleRequest").call(withArguments:[id,"",error.localizedDescription]) }
            }
        }
        let progress: @convention(block) (String,String) -> Void = { [weak self] id,progress in self?.callbacks[id]?(progress) }
        let result: @convention(block) (String,String,String) -> Void = { [weak self] id,text,error in
            guard let self, let continuation = self.completions.removeValue(forKey:id) else { return }
            self.callbacks.removeValue(forKey:id)
            if error.isEmpty { continuation.resume(returning:Data(text.utf8)) } else { continuation.resume(throwing:APIError(message:error,status:0)) }
        }
        let timer: @convention(block) (String,Double) -> Void = { [weak self] id,delay in
            Task { @MainActor in try? await Task.sleep(for:.milliseconds(max(0,delay))); self?.context.objectForKeyedSubscript("fireTimer").call(withArguments:[id]) }
        }
        context.setObject(request,forKeyedSubscript:"nativeRequest" as NSString)
        context.setObject(progress,forKeyedSubscript:"nativeProgress" as NSString)
        context.setObject(result,forKeyedSubscript:"nativeResult" as NSString)
        context.setObject(timer,forKeyedSubscript:"nativeTimer" as NSString)
        if let url = Bundle.main.url(forResource:"FeedEngine",withExtension:"js"), let source = try? String(contentsOf:url) { context.evaluateScript(source) }
    }
    func run(_ kind: String, data: AccountData, user: String, page: Int = 1, progress: @escaping (String)->Void) async throws -> Data {
        guard scope == API.shared.generation else { throw CancellationError() }
        let id = UUID().uuidString
        let input = try JSONSerialization.jsonObject(with:JSONEncoder().encode(data))
        return try await withCheckedThrowingContinuation { continuation in
            completions[id] = continuation; callbacks[id] = progress
            context.exception = nil
            context.objectForKeyedSubscript("runFeed").call(withArguments:[kind,input,user,page,id])
            if let error = context.exception {
                completions.removeValue(forKey:id)?.resume(throwing:APIError(message:error.toString() ?? "تعذر تجهيز الصفحة",status:0)); callbacks.removeValue(forKey:id)
            }
        }
    }
}
