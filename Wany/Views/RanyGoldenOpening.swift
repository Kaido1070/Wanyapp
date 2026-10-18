import SwiftUI
import UIKit
import WebKit

// The approved canvas source is bundled verbatim. Native code transports the
// current account's local covers and controls lifecycle, never redraws the design.
@MainActor struct RanyApprovedBackground: UIViewRepresentable {
    let images: [UIImage]
    let accountID: String?
    let canStart: Bool
    let playOpening: Bool
    let onStarted: (Date) -> Void
    var onFailure: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator,name:"ranyBackground")
        let web = WKWebView(frame:.zero,configuration:configuration)
        web.isOpaque = false
        web.backgroundColor = UIColor(red:25/255,green:27/255,blue:29/255,alpha:1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.isScrollEnabled = false
        web.isUserInteractionEnabled = false
        web.isAccessibilityElement = false
        web.accessibilityElementsHidden = true
        web.isHidden = true
        web.accessibilityIdentifier = "rany.background.approved-canvas"
        context.coordinator.web = web
        web.navigationDelegate = context.coordinator
        context.coordinator.update(self)
        if let url = Bundle.main.url(forResource:"RanyApprovedBackground",withExtension:"html"),
           let source = try? String(contentsOf:url,encoding:.utf8) {
            web.loadHTMLString(source,baseURL:nil)
        } else { context.coordinator.fail() }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) { context.coordinator.update(self) }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { coordinator.dispose() }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        private var owner: String?
        private var identities: [ObjectIdentifier] = []
        private var token: String?
        private var configuredToken: String?
        private var preparedToken: String?
        private var reportedToken: String?
        private var urls: [String]?
        private var loaded = false
        private var disposed = false
        private var failed = false
        private var active = false
        private var opening = true
        private var onStarted: (Date) -> Void = { _ in }
        private var onFailure: () -> Void = {}
        private var encoding: Task<Void,Never>?
        private struct Pool: @unchecked Sendable { let images: [UIImage] }

        func update(_ input: RanyApprovedBackground) {
            guard !disposed, !failed else { return }
            active = input.canStart; opening = input.playOpening
            onStarted = input.onStarted; onFailure = input.onFailure
            let nextIdentities = input.images.map(ObjectIdentifier.init)
            if token == nil || owner != input.accountID || identities != nextIdentities {
                encoding?.cancel()
                owner = input.accountID; identities = nextIdentities
                let next = UUID().uuidString
                token = next; configuredToken = nil; preparedToken = nil; reportedToken = nil; urls = nil
                // Hide and clear the preceding account before any new image is decoded.
                web?.isHidden = true
                if loaded { web?.callAsyncJavaScript("window.RanyBackground.clear(token)",arguments:["token":next],in:nil,contentWorld:.page,completionHandler:nil) }
                let pool = Pool(images:Array(input.images.prefix(14)))
                encoding = Task { [weak self] in
                    let worker = Task.detached(priority:.userInitiated) { Self.encode(pool) }
                    let encoded = await withTaskCancellationHandler(operation:{ await worker.value },onCancel:{ worker.cancel() })
                    guard let self, !Task.isCancelled, !self.disposed, self.token == next else { return }
                    self.urls = encoded; self.configureIfPossible()
                }
            } else if configuredToken == token {
                if active && preparedToken == token { web?.isHidden = false }
                web?.callAsyncJavaScript("window.RanyBackground.setActive(active)",arguments:["active":active],in:nil,contentWorld:.page,completionHandler:nil)
            } else { configureIfPossible() }
        }
        nonisolated private static func encode(_ pool: Pool) -> [String] {
            var result: [String] = []
            for image in pool.images {
                guard !Task.isCancelled else { return [] }
                // PNG preserves the pixels used by the approved reference's color pass.
                if let bytes = image.pngData() { result.append("data:image/png;base64,"+bytes.base64EncodedString()) }
            }
            return result
        }
        private func configureIfPossible() {
            guard !disposed, !failed, loaded, let token, let urls, configuredToken != token, let web else { return }
            configuredToken = token
            let payload: [String:Any] = ["token":token,"images":urls,"active":active,"opening":opening]
            web.callAsyncJavaScript("await window.RanyBackground.configure(payload); return true",arguments:["payload":payload],in:nil,contentWorld:.page) { [weak self] result in
                guard let self, self.token == token, !self.disposed else { return }
                if case .failure = result { self.fail() }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; configureIfPossible() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { fail() } }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { fail() } }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail() }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !disposed, !failed, let body = message.body as? [String:Any], body["token"] as? String == token else { return }
            switch body["event"] as? String {
            case "prepared":
                preparedToken = token
                if active { web?.isHidden = false }
            case "started":
                guard active else { return }
                web?.isHidden = false
                if reportedToken != token {
                    reportedToken = token
                    let elapsed = body["time"] as? Double ?? 0
                    onStarted(Date().addingTimeInterval(-min(4.3,max(0,elapsed))))
                }
            case "error": fail()
            default: break
            }
        }
        func fail() {
            guard !disposed, !failed else { return }
            failed = true; encoding?.cancel(); web?.isHidden = true
            let failure = onFailure; Task { @MainActor in failure() }
        }
        func dispose() {
            disposed = true; encoding?.cancel(); urls = nil
            web?.isHidden = true
            web?.configuration.userContentController.removeScriptMessageHandler(forName:"ranyBackground")
            web?.navigationDelegate = nil; web?.stopLoading()
        }
    }
}
