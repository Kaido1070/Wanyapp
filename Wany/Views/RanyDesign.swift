import SwiftUI
import UIKit
import CoreText

enum RanyTypography {
    static func registerFont() {
        guard UIFont(name:RanyIdentity.fontName,size:17) == nil, let url = Bundle.main.url(forResource:"RanyScript",withExtension:"otf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
    }
    static func font(_ style: Font.TextStyle) -> Font {
        .system(style)
    }
    static let brandColor = Color(red:223.0/255,green:193.0/255,blue:149.0/255)
    static func script(_ size: CGFloat) -> Font { .custom(RanyIdentity.fontName,size:size,relativeTo:.title) }
}

private struct RanyGlassProgressKey: EnvironmentKey { static let defaultValue: Double = 1 }
extension EnvironmentValues {
    var ranyGlassProgress: Double {
        get { self[RanyGlassProgressKey.self] }
        set { self[RanyGlassProgressKey.self] = newValue }
    }
}
struct RanyGlass: ViewModifier {
    var radius: CGFloat = 22
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ranyGlassProgress) private var progress
    @AppStorage(RanyAppearanceKeys.glass) private var enabled = true
    @AppStorage(RanyAppearanceKeys.blur) private var blur = RanyBlurLevel.balanced.rawValue
    @State private var revealed: Double = 0
    private var level: RanyBlurLevel { RanyBlurLevel(rawValue:blur) ?? .balanced }
    // The real iOS materials from 1.3.3. Animate their opacity, not a paused
    // UIVisualEffectView animator (which rendered opaque surfaces on device).
    private var material: AnyShapeStyle {
        switch level {
        case .clear: return AnyShapeStyle(Theme.surface.opacity(0.14))
        case .light: return AnyShapeStyle(.ultraThinMaterial)
        case .balanced: return AnyShapeStyle(.regularMaterial)
        case .strong: return AnyShapeStyle(.thickMaterial)
        }
    }
    @ViewBuilder func body(content: Content) -> some View {
        if !enabled || reduceTransparency {
            content.background(Theme.surface,in:RoundedRectangle(cornerRadius:radius,style:.continuous))
        } else {
            content.background {
                RoundedRectangle(cornerRadius:radius,style:.continuous)
                    .fill(material)
                    .opacity(revealed)
            }.overlay {
                RoundedRectangle(cornerRadius:radius,style:.continuous)
                    .stroke(LinearGradient(colors:[.white.opacity(0.17),Theme.accent.opacity(0.06),.white.opacity(0.04)],
                                           startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.7)
            }
            .onAppear { updateReveal() }
            .onChange(of:progress) { _,_ in updateReveal() }
            .onChange(of:blur) { _,_ in updateReveal() }
        }
    }
    private func updateReveal() {
        let value = min(1,max(0,progress))
        if reduceMotion { revealed = value }
        else { withAnimation(.easeInOut(duration:0.95)) { revealed = value } }
    }
}
extension View { func ranyGlass(radius: CGFloat = 22) -> some View { modifier(RanyGlass(radius:radius)) } }

// Fractional UIKit material avoids inserting a fully blurred layer at the handoff.
private struct RanyProgressiveMaterial: View, Animatable {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    var body: some View { RanyFractionalBlur(progress:progress) }
}
private struct RanyFractionalBlur: UIViewRepresentable {
    let progress: Double
    func makeUIView(context: Context) -> BlurView { BlurView() }
    func updateUIView(_ view: BlurView, context: Context) { view.update(progress:progress) }
    static func dismantleUIView(_ view: BlurView, coordinator: ()) { view.animator?.stopAnimation(true) }
    final class BlurView: UIVisualEffectView {
        var animator: UIViewPropertyAnimator?
        init() { super.init(effect:nil); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func update(progress: Double) {
            if animator == nil {
                effect = nil
                let style: UIBlurEffect.Style = .systemThickMaterialDark
                let animation = UIViewPropertyAnimator(duration:1,curve:.linear) { [weak self] in self?.effect = UIBlurEffect(style:style) }
                animation.pausesOnCompletion = true; animation.startAnimation(); animation.pauseAnimation(); animator = animation
            }
            animator?.fractionComplete = min(0.999,max(0,CGFloat(progress)))
        }
    }
}

struct RanyInsetGlass: ViewModifier {
    var radius: CGFloat = 15
    func body(content: Content) -> some View {
        content.ranyGlass(radius:radius)
    }
}
extension View { func ranyInsetGlass(radius: CGFloat = 15) -> some View { modifier(RanyInsetGlass(radius:radius)) } }

struct RanyMark: View {
    var size: CGFloat = 96
    var illuminated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ranyMarkCovered) private var covered
    @State private var shine: CGFloat = -1.5
    var body: some View {
        Image("RanyMonogram").resizable().scaledToFit().frame(width:size,height:size)
            .ranyGlass(radius:size*0.25)
            .overlay {
                LinearGradient(colors:[.clear,.white.opacity(0.18),.clear],startPoint:.leading,endPoint:.trailing)
                    .frame(width:size*0.42,height:size*1.7).rotationEffect(.degrees(23)).offset(x:shine*size)
            }.clipShape(RoundedRectangle(cornerRadius:size*0.25,style:.continuous)).accessibilityLabel(RanyIdentity.name)
            .environment(\.ranyGlassProgress,1)
            .opacity(covered ? 0 : 1)
            .task(id:illuminated) {
                guard illuminated, !reduceMotion else { return }
                withAnimation(.easeInOut(duration:0.72)) { shine = 1.5 }
            }
    }
}

struct RanyLoginView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var modeHighlight
    @State private var creating = false
    @State private var created = false
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var question = ""
    @State private var answer = ""
    @State private var busy = false
    @State private var recovery = false
    init(creatingAccount: Bool = false) { _creating = State(initialValue:creatingAccount) }
    private enum Field: Hashable { case username,password,confirmation,question,answer }
    @FocusState private var focus: Field?
    private var valid: Bool {
        guard !username.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, !password.isEmpty else { return false }
        guard creating && !created else { return true }
        let normalized = username.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        return normalized.range(of:"^[a-z0-9][a-z0-9_]{2,31}$",options:.regularExpression) != nil && (8...128).contains(password.utf16.count) && confirmation == password && (6...200).contains(question.trimmingCharacters(in:.whitespacesAndNewlines).utf16.count) && (1...128).contains(answer.trimmingCharacters(in:.whitespacesAndNewlines).utf16.count)
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing:0) {
                    RanyMark(size:92).reportRanyMarkFrame("login").padding(.top,geometry.size.height > 650 ? 38 : 16)
                    Text(creating ? "مساحتك تبدأ من هنا" : "هنا تبدأ حكايتك").font(.system(size:28,weight:.medium)).padding(.top,24)
                    Text(creating ? "حكايات كثيرة، ومكتبة تصبح لك" : "قصص تختارها، وعالم يشبهك").font(RanyTypography.font(.footnote)).foregroundStyle(.secondary).padding(.top,7)
                    HStack(spacing:4) {
                        modeButton("تسجيل الدخول",isCreation:false)
                        modeButton("إنشاء حساب",isCreation:true)
                    }.padding(4).ranyInsetGlass(radius:24).padding(.top,24)
                    VStack(alignment:.leading,spacing:15) {
                        Text(created ? "حسابك جاهز" : (creating ? "أهلًا ببدايتك الجديدة" : "مرحبًا بك")).font(RanyTypography.font(.headline))
                        Text(created ? "سجّل دخولك لفتح مكتبتك الجديدة" : (creating ? "حساب واحد للتطبيق والموقع" : "أكمل رحلتك من حيث توقفت")).font(RanyTypography.font(.caption)).foregroundStyle(.secondary).padding(.top,-8)
                        field("اسم المستخدم",icon:"person") {
                            TextField("اسم المستخدم",text:$username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus,equals:.username).submitLabel(.next).onSubmit { focus = .password }
                        }
                        field("كلمة المرور",icon:"lock") {
                            SecureField(creating ? "٨ أحرف أو أكثر" : "كلمة المرور",text:$password).textContentType(creating ? .newPassword : .password).focused($focus,equals:.password).submitLabel(creating ? .next : .go).onSubmit { if creating { focus = .confirmation } else { submit() } }
                        }
                        if creating && !created {
                            VStack(spacing:15) {
                                field("تأكيد كلمة المرور",icon:"lock.shield") { SecureField("أعد كتابة كلمة المرور",text:$confirmation).textContentType(.newPassword).focused($focus,equals:.confirmation).submitLabel(.next).onSubmit { focus = .question } }
                                field("سؤال الأمان",icon:"questionmark.circle") { TextField("سؤال تتذكر إجابته · ٦ أحرف أو أكثر",text:$question).focused($focus,equals:.question).submitLabel(.next).onSubmit { focus = .answer } }
                                field("إجابة الأمان",icon:"key") { SecureField("إجابتك لاستعادة الحساب",text:$answer).focused($focus,equals:.answer).submitLabel(.go).onSubmit { submit() } }
                            }.transition(.asymmetric(insertion:.offset(y:12).combined(with:.opacity),removal:.opacity))
                        }
                        Button(action:submit) {
                            HStack(spacing:12) { if busy { ProgressView().tint(Theme.accent) }; Text(creating && !created ? "إنشاء مكتبتي" : "الدخول إلى مكتبتي"); Image(systemName:"arrow.left") }
                                .font(RanyTypography.font(.subheadline)).foregroundStyle(Theme.accent).frame(maxWidth:.infinity,minHeight:51)
                                .background(LinearGradient(colors:[Theme.accent.opacity(0.24),Theme.accent.opacity(0.12)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:15))
                        }.buttonStyle(.plain).disabled(busy || !valid).opacity(busy || !valid ? 0.65 : 1)
                    }.padding(20).ranyGlass(radius:27).padding(.top,18).disabled(busy)
                    if !creating { Button("نسيت كلمة المرور؟") { recovery=true }.font(.footnote).padding(.top,18) }
                    Text(creating ? "احتفظ بإجابة الأمان؛ تحتاجها لاستعادة حسابك." : "استخدم حسابك الحالي في الموقع").font(RanyTypography.font(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top,18)
                    Text(AppVersion.display).font(RanyTypography.font(.caption2)).foregroundStyle(.tertiary).padding(.top,20).padding(.bottom,24)
                }.frame(maxWidth:430).frame(maxWidth:.infinity).padding(.horizontal,26).frame(minHeight:geometry.size.height,alignment:.top)
            }.scrollDismissesKeyboard(.interactively)
        }.onChange(of:username) { _,_ in created = false }
        .sheet(isPresented:$recovery) { AccountRecoveryView() }
    }
    private func modeButton(_ title: String, isCreation: Bool) -> some View {
        Button {
            guard !busy, creating != isCreation else { return }; focus = nil
            withAnimation(reduceMotion ? .linear(duration:0.05) : .spring(response:0.48,dampingFraction:0.88)) { creating = isCreation }
        } label: {
            Text(title).font(RanyTypography.font(.subheadline)).frame(maxWidth:.infinity,minHeight:42)
                .background { if creating == isCreation { Capsule().fill(Theme.accent.opacity(0.18)).matchedGeometryEffect(id:"auth-mode",in:modeHighlight) } }
        }.buttonStyle(.plain).disabled(busy).accessibilityAddTraits(creating == isCreation ? .isSelected : [])
    }
    private func field<C: View>(_ title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment:.leading,spacing:7) {
            Label(title,systemImage:icon).font(RanyTypography.font(.caption)).foregroundStyle(.secondary)
            content().font(RanyTypography.font(.body))
        }.padding(13).ranyInsetGlass(radius:15)
    }
    private func submit() {
        guard !busy,valid else { return }; focus = nil; busy = true
        Task {
            if creating && !created {
                created = await store.register(username:username,password:password,confirmation:confirmation,question:question,answer:answer)
                guard created else { busy = false; return }
                confirmation = ""; answer = ""
            }
            await store.login(username:username,password:password,freshAccount:created)
            if store.state != nil { password = ""; confirmation = ""; answer = "" }
            busy = false
        }
    }
}

// Global frames avoid RTL mirroring and guessed safe-area offsets at the intro handoff.
struct RanyMarkFrameKey: PreferenceKey {
    static var defaultValue: [String:CGRect] = [:]
    static func reduce(value: inout [String:CGRect], nextValue: () -> [String:CGRect]) {
        value.merge(nextValue(),uniquingKeysWith:{ _,new in new })
    }
}
private struct RanyMarkCoveredKey: EnvironmentKey { static let defaultValue = false }
private struct RanyMeasureMarkFramesKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var ranyMeasureMarkFrames: Bool {
        get { self[RanyMeasureMarkFramesKey.self] }
        set { self[RanyMeasureMarkFramesKey.self] = newValue }
    }
    var ranyMarkCovered: Bool {
        get { self[RanyMarkCoveredKey.self] }
        set { self[RanyMarkCoveredKey.self] = newValue }
    }
}
private struct RanyMarkFrameReporter: ViewModifier {
    let identity: String
    @Environment(\.ranyMeasureMarkFrames) private var measuring
    func body(content: Content) -> some View {
        content.background {
            if measuring {
                GeometryReader { geometry in
                    Color.clear.preference(key:RanyMarkFrameKey.self,value:[identity:geometry.frame(in:.global)])
                }
            }
        }
    }
}
extension View {
    func reportRanyMarkFrame(_ identity: String) -> some View {
        modifier(RanyMarkFrameReporter(identity:identity))
    }
}
