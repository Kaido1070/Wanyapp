import SwiftUI

// NavigationLink owns the interactive push/pop. Do not insert a UIKit lifecycle
// observer or snapshot layer inside its transparent destination; those layers
// can leave the outgoing page painted over the incoming one.
struct WanyLink<Destination: View, Label: View>: View {
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
        } label: { label() }

    }
}

extension WanyLink where Label == Text {
    init(_ title: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.init(destination:destination,label:{ Text(title) })
    }
}
