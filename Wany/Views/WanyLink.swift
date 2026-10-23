import SwiftUI

struct WanyLink<Label: View>: View {
    private let route: RanyRoute
    private let label: () -> Label
    init(_ route: RanyRoute, @ViewBuilder label: @escaping () -> Label) {
        self.route = route; self.label = label
    }
    var body: some View { NavigationLink(value:route) { label() } }
}

extension WanyLink where Label == Text {
    init(_ title: String, route: RanyRoute) {
        self.init(route) { Text(title) }
    }
}
