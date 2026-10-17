import SwiftUI
import UIKit

struct RanyRoute: Hashable { let id = UUID() }

// Change the native path only while its entire content is invisible. There is
// no native slide, snapshot, or second wallpaper competing with the next page.
@MainActor final class RanyNavigator: ObservableObject {
    @Published private(set) var path: [RanyRoute] = []
    @Published private(set) var opacity = 1.0
    @Published private(set) var transitioning = false
    private var destinations: [RanyRoute:AnyView] = [:]
    private var transitionTask: Task<Void,Never>?
    var reduceMotion = false
    func reset() {
        transitionTask?.cancel(); transitionTask = nil
        var transaction = Transaction(animation:nil); transaction.disablesAnimations = true
        withTransaction(transaction) { path = []; destinations = [:]; opacity = 1; transitioning = false }
    }

    func push(_ view: AnyView) {
        guard !transitioning else { return }
        let route = RanyRoute()
        transition { self.destinations[route] = view; self.path.append(route) }
    }
    func pop() {
        guard !transitioning, !path.isEmpty else { return }
        transition { let removed = self.path.removeLast(); self.destinations[removed] = nil }
    }
    func destination(_ route: RanyRoute) -> AnyView { destinations[route] ?? AnyView(EmptyView()) }
    func restore(_ newPath: [RanyRoute]) {
        guard newPath != path, !transitioning, newPath.count < path.count else { return }
        transition {
            let retained = Set(newPath)
            self.destinations = self.destinations.filter { retained.contains($0.key) }
            self.path = newPath
        }
    }
    private func transition(_ change: @escaping () -> Void) {
        transitioning = true
        transitionTask = Task { @MainActor in
            if !reduceMotion {
                withAnimation(.easeOut(duration:0.12)) { opacity = 0 }
                do { try await Task.sleep(for:.milliseconds(140)) } catch { return }
            }
            var transaction = Transaction(animation:nil); transaction.disablesAnimations = true
            withTransaction(transaction) { opacity = 0; change() }
            // Give NavigationStack a rendered frame to remove the previous tree.
            do { try await Task.sleep(for:.milliseconds(50)) } catch { return }
            if reduceMotion { opacity = 1 }
            else {
                withAnimation(.easeIn(duration:0.16)) { opacity = 1 }
                do { try await Task.sleep(for:.milliseconds(180)) } catch { return }
            }
            transitioning = false
        }
    }
}
private struct RanyNavigatorKey: EnvironmentKey { static let defaultValue: RanyNavigator? = nil }
extension EnvironmentValues {
    var ranyNavigator: RanyNavigator? {
        get { self[RanyNavigatorKey.self] }
        set { self[RanyNavigatorKey.self] = newValue }
    }
}

struct RanySequentialDestination: View {
    @ObservedObject var navigator: RanyNavigator
    let route: RanyRoute
    @Environment(\.layoutDirection) private var direction
    var body: some View {
        navigator.destination(route)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button { navigator.pop() } label: { Image(systemName: direction == .rightToLeft ? "chevron.right" : "chevron.left") }
                        .accessibilityLabel("رجوع")
                }
            }
            .background(RanyDisableNativeSwipe())
            .simultaneousGesture(DragGesture(minimumDistance:30).onEnded { value in
                let edge = direction == .rightToLeft ? UIScreen.main.bounds.width - value.startLocation.x : value.startLocation.x
                let travel = direction == .rightToLeft ? -value.translation.width : value.translation.width
                if edge < 28, travel > 70, abs(value.translation.height) < 70 { navigator.pop() }
            })
    }
}
// A back edge swipe uses the same sequential transition as the back button.
// Leave SwiftUI's navigation delegate alone.
private struct RanyDisableNativeSwipe: UIViewControllerRepresentable {
    func makeUIViewController(context:Context) -> Controller { Controller() }
    func updateUIViewController(_ controller:Controller,context:Context) {}
    final class Controller: UIViewController {
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated:Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
    }
}
