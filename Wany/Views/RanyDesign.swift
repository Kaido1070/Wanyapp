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
// One glass surface for cards, fields, bars and floating controls. iOS 26 renders
// the system Liquid Glass; iOS 17 and 18 use the system materials. The appearance
// settings (glass on/off and its strength) and Reduce Transparency apply to both.
struct RanyGlass: ViewModifier {
    var radius: CGFloat = 22
    // A bar that runs to the top screen edge: only its bottom corners are rounded.
    var topFlush = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ranyGlassProgress) private var progress
    @AppStorage(RanyAppearanceKeys.glass) private var enabled = true
    @AppStorage(RanyAppearanceKeys.blur) private var blur = RanyBlurLevel.balanced.rawValue
    @State private var revealed: Double = 0
    private var level: RanyBlurLevel { RanyBlurLevel(rawValue:blur) ?? .balanced }
    private var shape: AnyShape {
        topFlush ? AnyShape(UnevenRoundedRectangle(bottomLeadingRadius:radius,bottomTrailingRadius:radius,style:.continuous))
                 : AnyShape(RoundedRectangle(cornerRadius:radius,style:.continuous))
    }
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
            // Without glass, nested solid surfaces would merge (a story card on the library
            // card). A hairline edge and a lifted fill keep every card distinct.
            content.background(Theme.surface.opacity(0.92),in:shape)
                .background(Color.white.opacity(0.03),in:shape)
                .overlay { shape.stroke(Color.white.opacity(0.14),lineWidth:1) }
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) { content.glassEffect(liquidGlass,in:shape) }
            else { materialSurface(content) }
            #else
            materialSurface(content)
            #endif
        }
    }
    #if compiler(>=6.2)
    @available(iOS 26.0, *) private var liquidGlass: Glass {
        switch level {
        case .clear: return .clear
        case .light: return .regular
        case .balanced: return .regular.tint(Theme.surface.opacity(0.35))
        case .strong: return .regular.tint(Theme.surface.opacity(0.7))
        }
    }
    #endif
    private func materialSurface(_ content: Content) -> some View {
        content.background {
            shape.fill(material).opacity(revealed)
        }.overlay {
            shape.stroke(LinearGradient(colors:[.white.opacity(0.17),Theme.accent.opacity(0.06),.white.opacity(0.04)],
                                        startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.7)
        }
        .onAppear { updateReveal() }
        .onChange(of:progress) { _,_ in updateReveal() }
        .onChange(of:blur) { _,_ in updateReveal() }
    }
    private func updateReveal() {
        let value = min(1,max(0,progress))
        if reduceMotion { revealed = value }
        else { withAnimation(.easeInOut(duration:0.95)) { revealed = value } }
    }
}
extension View {
    func ranyGlass(radius: CGFloat = 22) -> some View { modifier(RanyGlass(radius:radius)) }
    func ranyTopBarGlass(radius: CGFloat = 26) -> some View { modifier(RanyGlass(radius:radius,topFlush:true)) }
}

struct RanyInsetGlass: ViewModifier {
    var radius: CGFloat = 15
    func body(content: Content) -> some View {
        content.ranyGlass(radius:radius)
    }
}
extension View { func ranyInsetGlass(radius: CGFloat = 15) -> some View { modifier(RanyInsetGlass(radius:radius)) } }

// The header mark sits directly inside the navigation bar's own circle. iOS 26
// draws that circle as Liquid Glass; iOS 17 and 18 get the same circle in glass.
struct RanyToolbarMark: View {
    @Environment(\.ranyMarkCovered) private var covered
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Image("RanyMonogram").resizable().scaledToFit().frame(width:30,height:30)
                    .opacity(covered ? 0 : 1).accessibilityLabel(RanyIdentity.name)
            } else {
                RanyMark(size:34,roundness:0.5)
            }
        }.reportRanyMarkFrame("header")
    }
}
struct RanyMark: View {
    var size: CGFloat = 96
    var illuminated = false
    var shineProgress: CGFloat? = nil
    // 0.25 is the rounded-square mark; 0.5 is the circular navigation-bar mark.
    var roundness: CGFloat = 0.25
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ranyMarkCovered) private var covered
    @State private var shine: CGFloat = -1.5
    var body: some View {
        Image("RanyMonogram").resizable().scaledToFit().frame(width:size,height:size)
            .ranyGlass(radius:size*roundness)
            .overlay {
                LinearGradient(colors:[.clear,.white.opacity(0.18),.clear],startPoint:.leading,endPoint:.trailing)
                    .frame(width:size*0.42,height:size*1.7).rotationEffect(.degrees(23)).offset(x:(shineProgress ?? shine)*size)
            }.clipShape(RoundedRectangle(cornerRadius:size*roundness,style:.continuous)).accessibilityLabel(RanyIdentity.name)
            .environment(\.ranyGlassProgress,1)
            .opacity(covered ? 0 : 1)
            .task(id:illuminated) {
                guard illuminated, !reduceMotion else { return }
                withAnimation(.easeInOut(duration:0.72)) { shine = 1.5 }
            }
    }
}

struct RanyLoginView: View {
    @Environment(AppStore.self) private var store
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
                            HStack(spacing:12) { if busy { ProgressView().tint(.black) }; Text(creating && !created ? "إنشاء مكتبتي" : "الدخول إلى مكتبتي"); Image(systemName:"arrow.left") }
                                .font(RanyTypography.font(.headline)).foregroundStyle(Color.black).frame(maxWidth:.infinity,minHeight:52)
                                .background(Theme.accent,in:RoundedRectangle(cornerRadius:15,style:.continuous))
                        }.buttonStyle(.plain).disabled(busy || !valid).opacity(busy || !valid ? 0.5 : 1)
                            .accessibilityIdentifier("login.submit")
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

// Window frames avoid RTL mirroring and guessed safe-area offsets at the intro handoff.
// The header mark lives in the native navigation bar, outside SwiftUI's preference
// tree, so the mark reports its UIKit window frame through an environment sink.
private struct RanyMarkCoveredKey: EnvironmentKey { static let defaultValue = false }
private struct RanyMeasureMarkFramesKey: EnvironmentKey { static let defaultValue = false }
private struct RanyMarkFrameSinkKey: EnvironmentKey { static let defaultValue: ((String,CGRect)->Void)? = nil }
extension EnvironmentValues {
    var ranyMeasureMarkFrames: Bool {
        get { self[RanyMeasureMarkFramesKey.self] }
        set { self[RanyMeasureMarkFramesKey.self] = newValue }
    }
    var ranyMarkCovered: Bool {
        get { self[RanyMarkCoveredKey.self] }
        set { self[RanyMarkCoveredKey.self] = newValue }
    }
    var ranyMarkFrameSink: ((String,CGRect)->Void)? {
        get { self[RanyMarkFrameSinkKey.self] }
        set { self[RanyMarkFrameSinkKey.self] = newValue }
    }
}
private struct RanyMarkFrameReporter: ViewModifier {
    let identity: String
    @Environment(\.ranyMeasureMarkFrames) private var measuring
    @Environment(\.ranyMarkFrameSink) private var sink
    func body(content: Content) -> some View {
        content.background {
            if measuring, let sink { RanyWindowFrameProbe { sink(identity,$0) } }
        }
    }
}
private struct RanyWindowFrameProbe: UIViewRepresentable {
    let report: (CGRect) -> Void
    func makeUIView(context: Context) -> Probe { let view = Probe(); view.report = report; return view }
    func updateUIView(_ view: Probe, context: Context) { view.report = report; view.publish() }
    final class Probe: UIView {
        var report: ((CGRect) -> Void)?
        private var last: CGRect = .null
        override init(frame: CGRect) { super.init(frame:frame); isUserInteractionEnabled = false; backgroundColor = .clear }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() { super.layoutSubviews(); publish() }
        override func didMoveToWindow() { super.didMoveToWindow(); publish() }
        func publish() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                let frame = self.convert(self.bounds,to:nil)
                guard frame.width > 0, frame.height > 0, frame != self.last else { return }
                self.last = frame; self.report?(frame)
            }
        }
    }
}
extension View {
    func reportRanyMarkFrame(_ identity: String) -> some View {
        modifier(RanyMarkFrameReporter(identity:identity))
    }
}
