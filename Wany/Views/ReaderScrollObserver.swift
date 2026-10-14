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
    var onScroll: (CGFloat, Bool) -> Void
    func makeUIView(context: Context) -> Probe { let view = Probe(); view.onScroll = onScroll; return view }
    func updateUIView(_ view: Probe, context: Context) { view.onScroll = onScroll; view.attach() }
    static func dismantleUIView(_ view: Probe, coordinator: Void) { view.observation = nil }
    final class Probe: UIView {
        var onScroll: ((CGFloat, Bool) -> Void)?
        var observation: NSKeyValueObservation?
        weak var observed: UIScrollView?
        override func didMoveToSuperview() { super.didMoveToSuperview(); attach() }
        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
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
                            let moving = scroll.isDragging || scroll.isDecelerating
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
