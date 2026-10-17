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

struct RanyGlass: ViewModifier {
    var radius: CGFloat = 22
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(Theme.surface.opacity(0.22)),in:.rect(cornerRadius:radius))
        } else { fallback(content) }
        #else
        fallback(content)
        #endif
    }
    private func fallback(_ content: Content) -> some View {
        content.background(Theme.surface.opacity(reduceTransparency ? 1 : 0.18),in:RoundedRectangle(cornerRadius:radius,style:.continuous))
            .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:radius,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).stroke(LinearGradient(colors:[.white.opacity(0.17),Theme.accent.opacity(0.06),.white.opacity(0.04)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.7))
    }
}
extension View { func ranyGlass(radius: CGFloat = 22) -> some View { modifier(RanyGlass(radius:radius)) } }

struct RanyInsetGlass: ViewModifier {
    var radius: CGFloat = 15
    func body(content: Content) -> some View {
        content.background(Theme.surface.opacity(0.25),in:RoundedRectangle(cornerRadius:radius,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).stroke(.white.opacity(0.075),lineWidth:0.7))
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
                            }.transition(.asymmetric(insertion:.move(edge:.trailing).combined(with:.opacity),removal:.opacity))
                        }
                        Button(action:submit) {
                            HStack(spacing:12) { if busy { ProgressView().tint(Theme.accent) }; Text(creating && !created ? "إنشاء مكتبتي" : "الدخول إلى مكتبتي"); Image(systemName:"arrow.left") }
                                .font(RanyTypography.font(.subheadline)).foregroundStyle(Theme.accent).frame(maxWidth:.infinity,minHeight:51)
                                .background(LinearGradient(colors:[Theme.accent.opacity(0.24),Theme.accent.opacity(0.12)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:15))
                        }.buttonStyle(.plain).disabled(busy || !valid).opacity(busy || !valid ? 0.65 : 1)
                    }.padding(20).ranyGlass(radius:27).padding(.top,18).disabled(busy)
                    Text(creating ? "احتفظ بإجابة الأمان؛ تحتاجها لاستعادة حسابك." : "استخدم حسابك الحالي في الموقع").font(RanyTypography.font(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top,18)
                    Text(AppVersion.display).font(RanyTypography.font(.caption2)).foregroundStyle(.tertiary).padding(.top,20).padding(.bottom,24)
                }.frame(maxWidth:430).frame(maxWidth:.infinity).padding(.horizontal,26).frame(minHeight:geometry.size.height,alignment:.top)
            }.scrollDismissesKeyboard(.interactively)
        }.onChange(of:username) { _,_ in created = false }
    }
    private func modeButton(_ title: String, isCreation: Bool) -> some View {
        Button {
            guard !busy else { return }; focus = nil
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
extension EnvironmentValues {
    var ranyMarkCovered: Bool {
        get { self[RanyMarkCoveredKey.self] }
        set { self[RanyMarkCoveredKey.self] = newValue }
    }
}
extension View {
    func reportRanyMarkFrame(_ identity: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key:RanyMarkFrameKey.self,value:[identity:geometry.frame(in:.global)])
        })
    }
}
