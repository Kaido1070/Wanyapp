import SwiftUI
import UIKit

// The hub lists each security task as one uniform row; every task opens its own
// page with labelled fields, live validation, a confirmation and a clear result.
struct AccountSecurityView: View {
    @Environment(AppStore.self) private var store
    @State private var question=""
    @State private var confirmLogout=false
    @State private var busy=false
    @State private var message: String?
    var body: some View {
        WanyScroll {
            Text("اختر ما تريد تغييره. كل خيار يطلب كلمة مرورك الحالية للتأكيد، ولا تُحفظ كلمة المرور على الجهاز.")
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            VStack(spacing:0) {
                WanyLink(.securityPassword) { SecurityHubRow(title:"تغيير كلمة المرور",detail:"6 أحرف على الأقل",icon:"key.fill") }
                Divider().padding(.leading,52)
                WanyLink(.securityQuestion) { SecurityHubRow(title:"سؤال الأمان",detail:question.isEmpty ? "غير محدد بعد" : question,icon:"questionmark.bubble.fill") }
                Divider().padding(.leading,52)
                WanyLink(.securityRecovery) { SecurityHubRow(title:"رمز الاستعادة",detail:"إصدار رمز جديد بعد التحقق",icon:"lifepreserver.fill") }
            }
            .buttonStyle(.plain)
            .ranyReadableSurface()
            Button(role:.destructive) { confirmLogout=true } label: {
                SecurityHubRow(title:"تسجيل الخروج من جميع الأجهزة",detail:"يُبطل كل الجلسات بما فيها هذا الجهاز",icon:"rectangle.portrait.and.arrow.right",destructive:true)
            }
            .buttonStyle(.plain)
            .ranyReadableSurface()
            .accessibilityIdentifier("security.logoutAll")
            if busy { ProgressView("جاري تسجيل الخروج…") }
            if let message { SecurityResultBanner(text:message,success:false) }
        }
        .navigationTitle("الأمان")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busy || !store.online || store.loginRequired)
        .confirmationDialog("الخروج من جميع الأجهزة؟",isPresented:$confirmLogout,titleVisibility:.visible) {
            Button("الخروج من جميع الأجهزة",role:.destructive) { logoutAll() }
            Button("إلغاء",role:.cancel) {}
        } message: { Text("ستُبطل جميع الجلسات، بما فيها هذا الجهاز. بيانات القراءة والتنزيلات محفوظة.") }
        .task {
            let owner=store.state?.user.id
            if let value=try? await API.shared.get("/api/security-question",as:JSONValue.self),owner == store.state?.user.id { question=value["question"].string }
        }
    }
    private func logoutAll() {
        busy=true; message=nil
        Task { @MainActor in
            defer { busy=false }
            do { try await store.logoutAllDevices() } catch { store.report(error); message=error.localizedDescription }
        }
    }
}

private struct SecurityHubRow: View {
    let title: String
    let detail: String
    let icon: String
    var destructive = false
    var body: some View {
        HStack(spacing:14) {
            Image(systemName:icon).font(.body.weight(.semibold))
                .foregroundStyle(destructive ? Color.red : Theme.accent)
                .frame(width:38,height:38)
                .background((destructive ? Color.red : Theme.accent).opacity(0.14),in:RoundedRectangle(cornerRadius:11,style:.continuous))
            VStack(alignment:.leading,spacing:3) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(destructive ? Color.red : Color.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength:8)
            if !destructive { Image(systemName:"chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth:.infinity,minHeight:58,alignment:.leading)
        .contentShape(Rectangle())
    }
}

// A labelled input with an optional hint that turns orange when the value is wrong.
private struct SecurityField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var secure = true
    var content: UITextContentType? = .password
    var hint: String? = nil
    var problem: String? = nil
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            Text(label).font(.subheadline.weight(.semibold))
            Group {
                if secure { SecureField(placeholder,text:$text) } else { TextField(placeholder,text:$text,axis:.vertical) }
            }
            .textContentType(content).textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(.horizontal,14).frame(minHeight:48)
            .background(Color.primary.opacity(0.07),in:RoundedRectangle(cornerRadius:12,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:12,style:.continuous).stroke(problem == nil ? Color.primary.opacity(0.14) : Color.orange.opacity(0.8),lineWidth:1))
            if let problem { Label(problem,systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
            else if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct SecurityResultBanner: View {
    let text: String
    let success: Bool
    var body: some View {
        Label(text,systemImage:success ? "checkmark.circle.fill" : "xmark.octagon.fill")
            .font(.callout).foregroundStyle(success ? Color.green : Color.orange)
            .frame(maxWidth:.infinity,alignment:.leading)
            .padding(14)
            .background((success ? Color.green : Color.orange).opacity(0.12),in:RoundedRectangle(cornerRadius:14,style:.continuous))
            .accessibilityIdentifier("security.result")
    }
}

// Shared shell for one security task: explanation, fields, a full-width action,
// a confirmation describing exactly what happens, and the server's verdict.
private struct SecurityTaskPage<Fields: View>: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    let title: String
    let explanation: String
    let action: String
    let confirmTitle: String
    let confirmMessage: String
    let ready: Bool
    let clear: () -> Void
    let perform: () async throws -> String
    @ViewBuilder let fields: () -> Fields
    @State private var busy=false
    @State private var confirm=false
    @State private var result: (text: String,success: Bool)?
    @State private var operation: Task<Void,Never>?
    var body: some View {
        WanyScroll {
            Text(explanation).font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            VStack(alignment:.leading,spacing:18) {
                fields()
                Button { confirm=true } label: {
                    HStack { if busy { ProgressView().tint(.black) }; Text(busy ? "جاري التحقق…" : action).font(.headline) }
                        .foregroundStyle(.black).frame(maxWidth:.infinity,minHeight:50)
                        .background(Theme.accent.opacity(ready && !busy ? 1 : 0.35),in:RoundedRectangle(cornerRadius:14,style:.continuous))
                }
                .buttonStyle(.plain)
                .disabled(!ready || busy)
            }
            .ranyReadableSurface()
            if let result { SecurityResultBanner(text:result.text,success:result.success) }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busy || !store.online || store.loginRequired)
        .confirmationDialog(confirmTitle,isPresented:$confirm,titleVisibility:.visible) {
            Button("تأكيد") { run() }
            Button("إلغاء",role:.cancel) {}
        } message: { Text(confirmMessage) }
        .onDisappear { operation?.cancel(); clear() }
        .onChange(of:phase) { _,value in if value != .active { operation?.cancel(); clear() } }
    }
    private func run() {
        guard !busy,let owner=store.state?.user.id else { return }
        busy=true; result=nil
        operation=Task { @MainActor in
            defer { busy=false }
            do {
                let text=try await perform()
                guard !Task.isCancelled,owner == store.state?.user.id else { return }
                result=(text,true)
            } catch {
                guard !Task.isCancelled else { return }
                result=(SecurityInput.explain(error),false)
            }
        }
    }
}

struct SecurityPasswordView: View {
    @Environment(AppStore.self) private var store
    @State private var current=""
    @State private var replacement=""
    @State private var confirmation=""
    var body: some View {
        SecurityTaskPage(
            title:"تغيير كلمة المرور",
            explanation:"اكتب كلمة مرورك الحالية ثم الجديدة مرتين. بعد الحفظ تبقى مسجلاً على هذا الجهاز، وتستخدم الجديدة في المرة القادمة.",
            action:"تغيير كلمة المرور",
            confirmTitle:"تغيير كلمة المرور؟",
            confirmMessage:"ستُستبدل كلمة المرور الحالية بالجديدة. إذا كانت الحالية غير صحيحة لن يتغير شيء.",
            ready:!current.isEmpty && SecurityInput.validPassword(replacement,confirmation:confirmation),
            clear:{ current=""; replacement=""; confirmation="" },
            perform:{
                try await API.shared.send("/api/change-password",value:["currentPassword":current,"newPassword":replacement])
                store.sessionRenewed(); current=""; replacement=""; confirmation=""
                return "تم تغيير كلمة المرور. استخدم الجديدة عند تسجيل الدخول القادم."
            }) {
            SecurityField(label:"كلمة المرور الحالية",placeholder:"اكتب كلمة مرورك الحالية",text:$current,hint:"للتحقق أنك صاحب الحساب.")
            SecurityField(label:"كلمة المرور الجديدة",placeholder:"6 أحرف على الأقل",text:$replacement,content:.newPassword,
                          hint:"من 6 إلى 128 حرفًا.",problem:SecurityInput.passwordProblem(replacement))
            SecurityField(label:"تأكيد كلمة المرور الجديدة",placeholder:"أعد كتابة الجديدة",text:$confirmation,content:.newPassword,
                          problem:!confirmation.isEmpty && confirmation != replacement ? "غير مطابقة لكلمة المرور الجديدة." : nil)
        }
    }
}

struct SecurityQuestionView: View {
    @Environment(AppStore.self) private var store
    @State private var current=""
    @State private var question=""
    @State private var answer=""
    @State private var existing=""
    var body: some View {
        SecurityTaskPage(
            title:"سؤال الأمان",
            explanation:"يُستخدم السؤال لاستعادة حسابك إذا نسيت كلمة المرور. اختر سؤالاً تتذكر إجابته ولا يعرفها غيرك.",
            action:existing.isEmpty ? "حفظ سؤال الأمان" : "تحديث سؤال الأمان",
            confirmTitle:"حفظ سؤال الأمان؟",
            confirmMessage:"سيحل السؤال والإجابة الجديدان محل السابقين.",
            ready:!current.isEmpty && SecurityInput.validQuestion(question,answer:answer),
            clear:{ current=""; answer="" },
            perform:{
                try await API.shared.send("/api/security-question",value:["currentPassword":current,"question":question,"answer":answer])
                existing=question; current=""; answer=""
                return "تم حفظ سؤال الأمان."
            }) {
            if !existing.isEmpty {
                VStack(alignment:.leading,spacing:4) {
                    Text("السؤال الحالي").font(.caption).foregroundStyle(.secondary)
                    Text(existing).font(.callout.weight(.medium))
                }
            }
            SecurityField(label:"كلمة المرور الحالية",placeholder:"اكتب كلمة مرورك الحالية",text:$current,hint:"للتحقق أنك صاحب الحساب.")
            SecurityField(label:"السؤال",placeholder:"مثال: اسم أول مدرسة درست فيها؟",text:$question,secure:false,content:nil,
                          hint:"من 6 إلى 200 حرف.",problem:SecurityInput.questionProblem(question))
            SecurityField(label:"الإجابة",placeholder:"اكتب الإجابة",text:$answer,content:nil,hint:"تُطلب حرفيًا عند الاستعادة.")
        }
        .task {
            let owner=store.state?.user.id
            if let value=try? await API.shared.get("/api/security-question",as:JSONValue.self),owner == store.state?.user.id {
                existing=value["question"].string; if question.isEmpty { question=existing }
            }
        }
    }
}

struct SecurityRecoveryView: View {
    @Environment(AppStore.self) private var store
    @State private var current=""
    @State private var code=""
    @State private var copied=false
    var body: some View {
        SecurityTaskPage(
            title:"رمز الاستعادة",
            explanation:"رمز الاستعادة يعيد لك حسابك إذا نسيت كلمة المرور. إصدار رمز جديد يلغي الرمز السابق فورًا، ولن يُحفظ داخل التطبيق.",
            action:"إصدار رمز جديد",
            confirmTitle:"إصدار رمز استعادة جديد؟",
            confirmMessage:"سيتوقف الرمز السابق عن العمل. احفظ الرمز الجديد فور ظهوره.",
            ready:!current.isEmpty,
            clear:{ current=""; code=""; copied=false },
            perform:{
                code=""; copied=false
                let result=try await API.shared.getMutation("/api/recovery-code",value:["currentPassword":current])
                current=""; code=result["recoveryCode"].string
                return "تم إصدار رمز جديد. احفظه الآن؛ يختفي عند مغادرة الصفحة."
            }) {
            SecurityField(label:"كلمة المرور الحالية",placeholder:"اكتب كلمة مرورك الحالية",text:$current,hint:"لن يُصدر رمز جديد قبل التحقق منها.")
            if !code.isEmpty {
                VStack(alignment:.leading,spacing:10) {
                    Text("رمزك الجديد").font(.subheadline.weight(.semibold))
                    Text(code).font(.system(.callout,design:.monospaced)).textSelection(.enabled)
                        .environment(\.layoutDirection,.leftToRight).privacySensitive()
                        .frame(maxWidth:.infinity,alignment:.leading).padding(12)
                        .background(Color.primary.opacity(0.07),in:RoundedRectangle(cornerRadius:12,style:.continuous))
                    Button(copied ? "تم النسخ" : "نسخ الرمز",systemImage:copied ? "checkmark" : "doc.on.doc") { UIPasteboard.general.string=code; copied=true }
                        .font(.callout.weight(.semibold))
                }
            }
        }
    }
}

enum SecurityInput {
    static func passwordProblem(_ value: String) -> String? {
        guard !value.isEmpty else { return nil }
        if value.utf16.count < 6 { return "قصيرة: 6 أحرف على الأقل." }
        if value.utf16.count > 128 { return "طويلة: 128 حرفًا كحد أقصى." }
        return nil
    }
    static func questionProblem(_ value: String) -> String? {
        let count=value.trimmingCharacters(in:.whitespacesAndNewlines).utf16.count
        guard count > 0 else { return nil }
        return (6...200).contains(count) ? nil : "السؤال يجب أن يكون من 6 إلى 200 حرف."
    }
    // The server's own message when it gives one; a plain explanation otherwise.
    static func explain(_ error: Error) -> String {
        if let error=error as? APIError {
            if error.status == 401 || error.status == 403 { return error.message.hasPrefix("تعذر إكمال الطلب") ? "كلمة المرور الحالية غير صحيحة. لم يتغير شيء." : error.message }
            if error.status == 429 { return "محاولات كثيرة. انتظر قليلاً ثم أعد المحاولة." }
            return error.message
        }
        return "تعذر إكمال الطلب. تأكد من الاتصال وأعد المحاولة."
    }
    static func validPassword(_ value: String,confirmation: String) -> Bool { (6...128).contains(value.utf16.count) && value == confirmation }
    static func validQuestion(_ question: String,answer: String) -> Bool {
        (6...200).contains(question.trimmingCharacters(in:.whitespacesAndNewlines).utf16.count) && (1...128).contains(answer.trimmingCharacters(in:.whitespacesAndNewlines).utf16.count)
    }
}

struct AccountRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var username=""
@State private var answer=""
@State private var code=""
@State private var password=""
@State private var confirmation=""
@State private var question=""
    @State private var byQuestion=true
    @State private var busy=false
    @State private var success=false
    @State private var message: String?
    @State private var confirm=false
    @State private var operation: Task<Void,Never>?
    var body: some View {
        NavigationStack {
            WanyScroll {
                VStack(alignment:.leading,spacing:16) {
                    TextField("اسم المستخدم",text:$username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("طريقة الاستعادة",selection:$byQuestion) { Text("سؤال الأمان").tag(true); Text("رمز الاستعادة").tag(false) }.pickerStyle(.segmented)
                    if byQuestion {
                        Button("عرض سؤال الأمان") { loadQuestion() }.disabled(username.isEmpty || busy)
                        if !question.isEmpty { Text(question).font(.callout) }
                        SecureField("إجابة الأمان",text:$answer).autocorrectionDisabled()
                    } else { SecureField("رمز الاستعادة",text:$code).textInputAutocapitalization(.never).autocorrectionDisabled() }
                    SecureField("كلمة المرور الجديدة · 6 أحرف على الأقل",text:$password).textContentType(.newPassword)
                    SecureField("تأكيد كلمة المرور",text:$confirmation).textContentType(.newPassword)
                    Button("استعادة الحساب") { confirm=true }
                        .disabled(username.isEmpty || !SecurityInput.validPassword(password,confirmation:confirmation) || (byQuestion ? answer.isEmpty : code.count < 20) || busy || success)
                    if busy { ProgressView() }
                    if let message { Text(message).foregroundStyle(success ? Theme.accent : .orange).font(.callout) }
                    if success { Button("العودة لتسجيل الدخول") { dismiss() } }
                }.card().disabled(busy)
            }.navigationTitle("استعادة الحساب")
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("إغلاق") { dismiss() } } }
                .confirmationDialog("تعيين كلمة مرور جديدة وإبطال الجلسات السابقة؟",isPresented:$confirm,titleVisibility:.visible) { Button("تأكيد الاستعادة") { recover() }; Button("إلغاء",role:.cancel) {} }
        }.environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark)
        .onDisappear { operation?.cancel(); clearSecrets() }
        .onChange(of:phase) { _,value in if value != .active { operation?.cancel(); clearSecrets() } }
        .onChange(of:username) { _,_ in question=""; answer=""; code=""; success=false }
    }
    private func clearSecrets() { answer=""; code=""; password=""; confirmation="" }
    private func loadQuestion() {
        let login=username; busy=true
        operation=Task { @MainActor in
            defer { busy=false }
            do {
                let value=try await API.shared.getMutation("/api/recover-password",value:["action":"question","username":login])
                guard !Task.isCancelled,username == login else { return }; question=value["question"].string
            } catch { if !Task.isCancelled { message=error.localizedDescription } }
        }
    }
    private func recover() {
        let body=["username":username,"newPassword":password,"method":byQuestion ? "security-question" : "recovery-code","answer":answer,"recoveryCode":code]
        busy=true; message=nil
        operation=Task { @MainActor in
            defer { busy=false; clearSecrets() }
            do {
                try await API.shared.send("/api/recover-password",value:body)
                guard !Task.isCancelled else { return }; success=true; message="تم تحديث كلمة المرور وإبطال الجلسات السابقة. سجّل الدخول بكلمة المرور الجديدة."
            } catch { if !Task.isCancelled { message=error.localizedDescription } }
        }
    }
}
