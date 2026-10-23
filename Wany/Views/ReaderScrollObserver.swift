import SwiftUI
import UIKit

// Observe the actual scroll offset, including deceleration, independently of lazy page layout.
struct ReaderScrollDirection {
    var revealDistance: CGFloat = 96
    private var previous: CGFloat?
    private var travel: CGFloat = 0
    init(revealDistance: CGFloat = 96) { self.revealDistance = revealDistance }
    mutating func update(offset: CGFloat, userScrolling: Bool) -> Bool? {
        defer { previous = offset }
        guard userScrolling, let previous else { travel = 0; return nil }
        if offset <= 16 { travel = 0; return true }
        let delta = offset - previous
        if delta == 0 { return nil }
        if (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta
        // Require a deliberate upward scroll before revealing the header.
        let threshold: CGFloat = travel < 0 ? revealDistance : 14
        guard abs(travel) >= threshold else { return nil }
        let visible = travel < 0
        travel = 0
        return visible
    }
}

struct ReaderScrollObserver: UIViewRepresentable {
    var scrollToTop = 0
    var onScroll: (CGFloat, Bool) -> Void
    func makeUIView(context: Context) -> Probe { let view = Probe(); view.onScroll = onScroll; view.topRequest = scrollToTop; return view }
    func updateUIView(_ view: Probe, context: Context) { view.onScroll = onScroll; view.attach(); view.scrollToTop(scrollToTop) }
    static func dismantleUIView(_ view: Probe, coordinator: Void) { view.observation = nil }
    final class Probe: UIView {
        var onScroll: ((CGFloat, Bool) -> Void)?
        var observation: NSKeyValueObservation?
        var topRequest = 0
        weak var observed: UIScrollView?
        override func didMoveToSuperview() { super.didMoveToSuperview(); attach() }
        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        // Re-selecting the current tab scrolls back to the top and expands the large title.
        func scrollToTop(_ request: Int) {
            guard request != topRequest else { return }
            topRequest = request
            guard let scroll = observed else { return }
            scroll.setContentOffset(CGPoint(x:-scroll.adjustedContentInset.left,y:-scroll.adjustedContentInset.top),animated:!UIAccessibility.isReduceMotionEnabled)
        }
        func attach() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                var ancestor = self.superview
                while let view = ancestor {
                    if let scroll = view as? UIScrollView {
                        guard self.observed !== scroll else { return }
                        self.observed = scroll
                        self.observation = scroll.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scroll, _ in
                            let offset = scroll.contentOffset.y + scroll.adjustedContentInset.top
                            // The rubber-band zone past either end is not a scroll direction: reacting
                            // to it (hiding the tab bar changes the insets) makes the page bounce in a loop.
                            let end = max(0,scroll.contentSize.height+scroll.adjustedContentInset.top+scroll.adjustedContentInset.bottom-scroll.bounds.height)
                            let bouncing = offset < 0 || offset > end
                            let moving = (scroll.isDragging || scroll.isDecelerating) && !bouncing
                            DispatchQueue.main.async { [weak self] in self?.onScroll?(offset, moving) }
                        }
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
}
