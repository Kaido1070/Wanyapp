import Foundation
import Combine

// Download counters from other chapters never invalidate the open reader.
@MainActor final class ReaderTransferState: ObservableObject {
    @Published private(set) var files: [URL?] = []
    private var payload: ChapterPayload?
    private var subscription: AnyCancellable?
    private let downloads = Downloads.shared
    init() {
        subscription = downloads.objectWillChange.throttle(for:.milliseconds(250),scheduler:DispatchQueue.main,latest:true).sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }
    func watch(_ payload: ChapterPayload) { self.payload = payload; refresh() }
    private func refresh() {
        guard let payload else { return }
        let next = payload.pages.indices.map { downloads.pageURL(payload,index:$0) }
        if next != files { files = next }
    }
}
