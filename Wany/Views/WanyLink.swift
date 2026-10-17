import SwiftUI

// Native transitions and cancelled back swipes report their final stack state.
struct WanyLink<Destination: View, Label: View>: View {
    @EnvironmentObject var store: AppStore
    private let destination: () -> Destination
    private let label: () -> Label
    init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination; self.label = label
    }
    var body: some View {
        NavigationLink {
            destination().environment(\.ranyMainHeader,false)
                .toolbar(ObjectIdentifier(Destination.self) == ObjectIdentifier(ReaderView.self) ? .hidden : .visible,for:.navigationBar)
                .ranyClearNavigation()
                .background(RanyNavigationLifecycle(main:false))
        } label: { label() }

    }
}

extension WanyLink where Label == Text {
    init(_ title: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.init(destination:destination,label:{ Text(title) })
    }
}
