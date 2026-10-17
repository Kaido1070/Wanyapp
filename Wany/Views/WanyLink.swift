import SwiftUI

struct WanyLink<Destination: View, Label: View>: View {
    @Environment(\.ranyNavigator) private var navigator
    private let destination: () -> Destination
    private let label: () -> Label
    init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination; self.label = label
    }
    var body: some View {
        Group {
            if let navigator {
                Button { navigator.push(AnyView(target)) } label: { label() }
            } else {
                NavigationLink { target } label: { label() }
            }
        }
    }
    private var target: some View {
        destination().environment(\.ranyMainHeader,false)
            .toolbar(ObjectIdentifier(Destination.self) == ObjectIdentifier(ReaderView.self) ? .hidden : .visible,for:.navigationBar)
            .ranyClearNavigation()

    }
}

extension WanyLink where Label == Text {
    init(_ title: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.init(destination:destination,label:{ Text(title) })
    }
}
