import SwiftUI
import UIKit

// Let the native navigation stack own bar visibility, including cancelled back swipes.
// A temporary image of the shared wallpaper shields outgoing text during transitions.
struct RanyNavigationLifecycle: UIViewControllerRepresentable {
    @EnvironmentObject var store: AppStore
    let main: Bool
    func makeUIViewController(context: Context) -> Observer { Observer() }
    func updateUIViewController(_ controller: Observer, context: Context) {
        controller.onVisibility = { [weak store] main in
            guard let store, store.mainPageVisible != main else { return }
            store.mainPageVisible = main
        }
        controller.isMain = main
    }
    final class Observer: UIViewController {
        var isMain = false
        var onVisibility: ((Bool)->Void)?
        private var wallpaper: UIImageView?
        override func loadView() { view = UIView(); view.backgroundColor = .clear; view.isUserInteractionEnabled = false }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); observeTransition() }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); observeTransition() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); publishVisibility(); clearShield() }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            if let image = wallpaper, let renderer = renderer(in:view.window) { image.frame = renderer.convert(renderer.bounds,to:view) }
        }
        private var navigation: UINavigationController? {
            var current: UIViewController? = self
            while let controller = current {
                if let nav = controller as? UINavigationController { return nav }
                if let nav = controller.navigationController { return nav }
                current = controller.parent
            }
            return nil
        }
        private func publishVisibility() {
            let main = navigation.map { $0.viewControllers.count <= 1 } ?? isMain
            DispatchQueue.main.async { [weak self] in self?.onVisibility?(main) }
        }
        private func observeTransition() {
            guard let coordinator = transitionCoordinator ?? navigation?.transitionCoordinator else { publishVisibility(); return }
            onVisibility?(false)
            if wallpaper == nil, let renderer = renderer(in:view.window), renderer.bounds.width > 0 {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                let image = UIGraphicsImageRenderer(bounds:renderer.bounds,format:format).image { _ in renderer.drawHierarchy(in:renderer.bounds,afterScreenUpdates:false) }
                let shield = UIImageView(image:image); shield.isUserInteractionEnabled = false
                shield.frame = renderer.convert(renderer.bounds,to:view); view.addSubview(shield); wallpaper = shield
            }
            coordinator.animate(alongsideTransition:nil) { [weak self] _ in self?.publishVisibility(); self?.clearShield() }
        }
        private func clearShield() { wallpaper?.removeFromSuperview(); wallpaper = nil }
        private func renderer(in view: UIView?) -> UIView? {
            guard let view else { return nil }
            if view.accessibilityIdentifier == "rany.background.renderer" { return view }
            for child in view.subviews { if let result = renderer(in:child) { return result } }
            return nil
        }
    }
}
