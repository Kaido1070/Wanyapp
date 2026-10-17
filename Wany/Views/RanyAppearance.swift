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
// renderer; pages and navigation containers reveal it instead of painting black.
private struct RanyClearNavigation: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.containerBackground(Color.clear,for:.navigation)
        } else {
            content.background(RanyLegacyClearNavigation())
        }
    }
}
extension View {
    func ranyClearNavigation() -> some View { modifier(RanyClearNavigation()) }
}
private struct RanyLegacyClearNavigation: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.clearNavigation() }
    final class Probe: UIView {
        override func didMoveToWindow() { super.didMoveToWindow(); clearNavigation() }
        func clearNavigation() {
            DispatchQueue.main.async { [weak self] in
                var responder: UIResponder? = self
                while let current = responder {
                    if let controller = current as? UIViewController, let navigation = controller.navigationController {
                        navigation.view.backgroundColor = .clear
                        navigation.viewControllers.forEach { $0.view.backgroundColor = .clear }
                        return
                    }
                    responder = current.next
                }
            }
        }
    }
}

private struct RanyMainHeaderKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var ranyMainHeader: Bool {
        get { self[RanyMainHeaderKey.self] }
        set { self[RanyMainHeaderKey.self] = newValue }
    }
}
struct RanyPageHeader: View {
    var body: some View {
        ZStack {
            Text(RanyIdentity.displayName).font(RanyTypography.script(27)).foregroundStyle(RanyTypography.brandColor).accessibilityLabel(RanyIdentity.name)
            HStack {
                RanyMark(size:32).reportRanyMarkFrame("header")
                Spacer()
                WanyLink { SettingsView() } label: {
                    Image(systemName:"gearshape").font(.system(size:22)).frame(width:44,height:44).contentShape(Rectangle())
                }.accessibilityLabel("الإعدادات").accessibilityIdentifier("main.settings")
            }
        }.frame(height:48).padding(.top,4).padding(.bottom,2).accessibilityIdentifier("main.header")
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
