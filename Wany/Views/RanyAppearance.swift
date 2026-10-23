import SwiftUI
import UIKit

enum RanyBlurLevel: Int, CaseIterable, Identifiable {
    case clear, light, balanced, strong
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .clear: return "شفاف"
        case .light: return "خفيف"
        case .balanced: return "متوازن"
        case .strong: return "قوي"
        }
    }
}
enum RanyAppearanceKeys {
    static let background = "rany.appearance.background"
    static let glass = "rany.appearance.glass"
    static let blur = "rany.appearance.blur"
}

struct RanyAppearanceControls: View {
    @AppStorage(RanyAppearanceKeys.background) private var background = true
    @AppStorage(RanyAppearanceKeys.glass) private var glass = true
    @AppStorage(RanyAppearanceKeys.blur) private var blur = RanyBlurLevel.balanced.rawValue
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Label("المظهر والخلفية",systemImage:"sparkles").font(.headline)
            Toggle("خلفية الأغلفة المتحركة",isOn:$background).accessibilityIdentifier("appearance.background")
            Text("أغلفة متابعاتك الواضحة، ويُكمَّل العدد بالأعمال المشهورة. إيقافها يوقف رسم الأغلفة وحركتها.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("التأثير الزجاجي",isOn:$glass).accessibilityIdentifier("appearance.glass")
            Text("ضبابية الزجاج").font(.subheadline)
            Picker("ضبابية الزجاج",selection:$blur) {
                ForEach(RanyBlurLevel.allCases) { level in Text(level.label).tag(level.rawValue) }
            }.pickerStyle(.segmented).disabled(!glass).accessibilityIdentifier("appearance.blur")
            Text("تُحفظ اختياراتك على الجهاز وتُطبّق مباشرة على الصناديق والبطاقات والخيارات. مع تقليل الشفافية في النظام تُستخدم أسطح واضحة القراءة.").font(.caption).foregroundStyle(.secondary)
        }.card()
    }
}

// Match Pany's navigation-container treatment: the background has one persistent
// renderer; pages, navigation and tab containers reveal it instead of painting black.
private struct RanyClearNavigation: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.containerBackground(Color.clear,for:.navigation).background(RanyClearContainers())
        } else {
            content.background(RanyClearContainers())
        }
    }
}
extension View {
    func ranyClearNavigation() -> some View { modifier(RanyClearNavigation()) }
}
private struct RanyClearContainers: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.clearContainers() }
    final class Probe: UIView {
        override func didMoveToWindow() { super.didMoveToWindow(); clearContainers() }
        func clearContainers() {
            DispatchQueue.main.async { [weak self] in
                var responder: UIResponder? = self
                while let current = responder, !(current is UIViewController) { responder = current.next }
                var controller = responder as? UIViewController
                // Clear every hosting wrapper between this page and the window root,
                // including the native TabView and each tab's NavigationStack.
                while let current = controller {
                    if current.view.window?.rootViewController === current { break }
                    current.view.backgroundColor = .clear
                    if let navigation = current as? UINavigationController { navigation.viewControllers.forEach { $0.viewIfLoaded?.backgroundColor = .clear } }
                    if let tabs = current as? UITabBarController { tabs.viewControllers?.forEach { $0.viewIfLoaded?.backgroundColor = .clear } }
                    controller = current.parent
                }
            }
        }
    }
}

private struct RanyGlassGroup: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing:0) { content } }
        else { content }
        #else
        content
        #endif
    }
}
extension View { func ranyGlassGroup() -> some View { modifier(RanyGlassGroup()) } }
