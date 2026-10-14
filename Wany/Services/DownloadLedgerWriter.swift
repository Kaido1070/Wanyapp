import Foundation

// Serialize durable snapshots away from touch handling, coalescing obsolete writes.
@MainActor final class DownloadLedgerWriter {
    private let queue = DispatchQueue(label:"site.wany.download-ledger",qos:.utility)
    private var pending: [String:[DownloadJob]] = [:]
    private var callbacks: [String:[(Error?) -> Void]] = [:]
    private var drainers: [CheckedContinuation<Void,Never>] = []
    private var running = false
    private(set) var latest: [String:[DownloadJob]] = [:]
    func save(_ jobs: [DownloadJob], owner: String, completion: ((Error?) -> Void)? = nil) {
        latest[owner] = jobs; pending[owner] = jobs
        if let completion { callbacks[owner,default:[]].append(completion) }
        start()
    }
    func flush() async {
        guard running || !pending.isEmpty else { return }
        await withCheckedContinuation { drainers.append($0) }
    }
    private func start() {
        guard !running else { return }
        guard let owner = pending.keys.first, let snapshot = pending.removeValue(forKey:owner) else {
            let waiting = drainers; drainers = []; waiting.forEach { $0.resume() }; return
        }
        running = true
        let completions = callbacks.removeValue(forKey:owner) ?? []
        queue.async {
            var error: Error?
            do { try Disk.save(snapshot,owner:owner,name:"downloads.json") } catch let failure { error = failure }
            DispatchQueue.main.async {
                completions.forEach { $0(error) }
                self.running = false; self.start()
            }
        }
    }
}
