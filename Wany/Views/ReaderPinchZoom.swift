import SwiftUI
import UIKit

// The chapter keeps its existing lazy page stack and native scrolling. Only a
// pinch changes its width; ordinary scrolling never writes a scroll anchor.
struct ReaderZoomAnchor {
    let point: CGPoint
    let initialScale: CGFloat
    static func scale(_ value: CGFloat) -> CGFloat { min(4,max(1,value)) }
    func offset(scale: CGFloat, focal: CGPoint, size: CGSize, viewport: CGSize, inset: UIEdgeInsets) -> CGPoint {
        let ratio = scale / initialScale
        return CGPoint(
            x:min(max(-inset.left,point.x * ratio - focal.x),max(-inset.left,size.width - viewport.width + inset.right)),
            y:min(max(-inset.top,point.y * ratio - focal.y),max(-inset.top,size.height - viewport.height + inset.bottom)))
    }
}

struct ReaderPinchZoom: UIViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var isPinching: Bool
    let baseWidth: CGFloat
    func makeUIView(context: Context) -> Probe { let view = Probe(); configure(view); return view }
    func updateUIView(_ view: Probe, context: Context) { configure(view); view.attach() }
    private func configure(_ view: Probe) {
        view.scale = scale; view.baseWidth = baseWidth
        view.onChange = { scale = $0 }
        view.onPinching = { isPinching = $0 }
    }
    static func dismantleUIView(_ view: Probe, coordinator: Void) { view.detach() }

    final class Probe: UIView, UIGestureRecognizerDelegate {
        var scale: CGFloat = 1
        var baseWidth: CGFloat = 1
        var onChange: ((CGFloat) -> Void)?
        var onPinching: ((Bool) -> Void)?
        weak var scroll: UIScrollView?
        var observation: NSKeyValueObservation?
        var anchor: ReaderZoomAnchor?
        var target: (scale:CGFloat,focal:CGPoint)?
        var ending = false
        lazy var pinch = UIPinchGestureRecognizer(target:self,action:#selector(handle(_:)))
        override func didMoveToSuperview() { super.didMoveToSuperview(); attach() }
        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        func attach() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                var ancestor = self.superview
                while let view = ancestor {
                    if let found = view as? UIScrollView { self.attach(to:found); return }
                    ancestor = view.superview
                }
            }
        }
        func attach(to found: UIScrollView) {
            guard scroll !== found else { return }
            detach(); scroll = found
            pinch.delegate = self; pinch.cancelsTouchesInView = false
            found.addGestureRecognizer(pinch)
            observation = found.observe(\.contentSize,options:[.new]) { [weak self] _,_ in
                DispatchQueue.main.async { [weak self] in self?.applyAnchor() }
            }
        }
        func detach() {
            observation = nil
            if anchor != nil { scroll?.panGestureRecognizer.isEnabled = true }
            scroll?.removeGestureRecognizer(pinch)
            scroll = nil; anchor = nil; target = nil; ending = false
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func handle(_ gesture: UIPinchGestureRecognizer) {
            guard let scroll else { return }
            let location = gesture.location(in:scroll)
            let focal = CGPoint(x:location.x - scroll.bounds.minX,y:location.y - scroll.bounds.minY)
            if gesture.state == .began { begin(at:location) }
            if gesture.state == .began || gesture.state == .changed || gesture.state == .ended { change(factor:gesture.scale,focal:focal) }
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed { end() }
        }
        func begin(at location: CGPoint) {
            guard let scroll else { return }
            ending = false
            anchor = ReaderZoomAnchor(point:location,initialScale:scale)
            // The pinch owns both fingers until release. Normal native panning
            // resumes at the new size without an extra reader or image overlay.
            scroll.panGestureRecognizer.isEnabled = false
            onPinching?(true)
        }
        func change(factor: CGFloat, focal: CGPoint) {
            guard let anchor else { return }
            let next = ReaderZoomAnchor.scale(anchor.initialScale * factor)
            target = (next,focal)
            if next != scale { scale = next; onChange?(next) }
            applyAnchor()
        }
        func end() {
            scroll?.panGestureRecognizer.isEnabled = true
            ending = true
            if target == nil { finish() } else { applyAnchor() }
            // If layout is still pending, contentSize observation will finish
            // the last anchor. Never discard it before the new width arrives.
        }
        func finish() { anchor = nil; target = nil; ending = false; onPinching?(false) }
        func applyAnchor() {
            guard let scroll, let anchor, let target,
                  abs(scroll.contentSize.width - baseWidth * target.scale) < 1 else { return }
            let offset = anchor.offset(scale:target.scale,focal:target.focal,size:scroll.contentSize,viewport:scroll.bounds.size,inset:scroll.adjustedContentInset)
            scroll.setContentOffset(offset,animated:false)
            if ending { finish() }
        }
    }
}
