import SwiftUI

// Keep native navigation, including swipe-back. Hide the main bar on the tap,
// instead of waiting for the outgoing view's delayed disappearance callback.
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
                .onAppear { store.mainPageVisible = false }
        } label: { label() }
        .simultaneousGesture(TapGesture().onEnded {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { store.mainPageVisible = false }
        })
    }
}

extension WanyLink where Label == Text {
    init(_ title: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.init(destination:destination,label:{ Text(title) })
    }
}
