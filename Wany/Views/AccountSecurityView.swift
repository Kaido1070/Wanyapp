import SwiftUI

struct AccountSecurityView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var phase
    @State private var currentPassword=""
@State private var newPassword=""
@State private var confirmation=""
@State private var question=""
@State private var answer=""
@State private var recoveryCode=""
    @State private var busy=false
    @State private var message: String?
    @State private var pending: Action?
    @State private var confirm=false
    @State private var operation: Task<Void,Never>?
    private enum Action: Equatable { case password, question, recovery, logoutAll }
    var body: some View {
        WanyScroll {
            VStack(alignment:.leading,spacing:14) {
                Text("الأمان والحساب").font(.title2.bold())
                SecureField("كلمة المرور الحالية",text:$currentPassword).textContentType(.password)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().padding(12).ranyInsetGlass(radius:12)
                Text("تُستخدم للتحقق من تغييرات الأمان ولا تُحفظ على الجهاز.").font(.caption).foregroundStyle(.secondary)
            }.card()
            VStack(alignment:.leading,spacing:14) {
                Text("تغيير كلمة المرور").font(.headline)
                SecureField("كلمة المرور الجديدة · 6 أحرف على الأقل",text:$newPassword).textContentType(.newPassword)
                SecureField("تأكيد كلمة المرور الجديدة",text:$confirmation).textContentType(.newPassword)
                Button("تغيير كلمة المرور") { ask(.password) }.disabled(!SecurityInput.validPassword(newPassword,confirmation:confirmation) || currentPassword.isEmpty)
            }.card()
            VStack(alignment:.leading,spacing:14) {
                Text("سؤال الأمان").font(.headline)
                TextField("السؤال · 6 إلى 200 حرف",text:$question)
                SecureField("الإجابة",text:$answer).textContentType(.none).autocorrectionDisabled()
                Button("حفظ سؤال الأمان") { ask(.question) }.disabled(!SecurityInput.validQuestion(question,answer:answer) || currentPassword.isEmpty)
            }.card()
            VStack(alignment:.leading,spacing:14) {
                Text("رمز الاستعادة").font(.headline)
                Text("إصدار رمز جديد يلغي الرمز السابق. احفظه في مكان آمن؛ لن يُحفظ داخل التطبيق.").font(.caption).foregroundStyle(.secondary)
                Button("إصدار رمز استعادة جديد") { ask(.recovery) }.disabled(currentPassword.isEmpty)
                if !recoveryCode.isEmpty {
                    Text("احفظ الرمز الآن؛ يختفي عند مغادرة الشاشة.").font(.caption)
                    Text(recoveryCode).font(.system(.callout,design:.monospaced)).textSelection(.enabled).environment(\.layoutDirection,.leftToRight).privacySensitive()
                }
            }.card()
            Button("تسجيل الخروج من جميع الأجهزة",role:.destructive) { ask(.logoutAll) }.frame(minHeight:48).card()
            if busy { ProgressView("جاري التحقق…") }
            if let message { Text(message).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("security.result") }
        }.navigationTitle("الأمان").disabled(busy || !store.online || store.loginRequired)
        .confirmationDialog("تأكيد تغيير إعدادات الأمان",isPresented:$confirm,titleVisibility:.visible) {
            Button(pending == .logoutAll ? "الخروج من جميع الأجهزة" : "تأكيد",role:pending == .logoutAll ? .destructive : nil) { execute() }
            Button("إلغاء",role:.cancel) { pending=nil }
        } message: { Text(pending == .logoutAll ? "ستُبطل جميع الجلسات، بما فيها هذا الجهاز. بيانات القراءة والتنزيلات محفوظة." : "ستُرسل البيانات مباشرة للتحقق بواسطة خادم الموقع.") }
        .task {
            let owner=store.state?.user.id
            if let value=try? await API.shared.get("/api/security-question",as:JSONValue.self),owner == store.state?.user.id { question=value["question"].string }
        }
        .onDisappear { operation?.cancel(); clearSecrets() }
        .onChange(of:phase) { _,value in if value != .active { operation?.cancel(); clearSecrets() } }
    }
    private func ask(_ action: Action) { pending=action; confirm=true }
    private func clearSecrets() { currentPassword=""; newPassword=""; confirmation=""; answer=""; recoveryCode="" }
    private func execute() {
        guard let action=pending,!busy,let owner=store.state?.user.id else { return }
        busy=true; message=nil; recoveryCode=""
        let password=currentPassword, replacement=newPassword, prompt=question, response=answer
        operation=Task { @MainActor in
            defer { busy=false; currentPassword=""; answer="" }
            do {
                switch action {
                case .password:
                    try await API.shared.send("/api/change-password",value:["currentPassword":password,"newPassword":replacement])
                    store.sessionRenewed()
                case .question:
                    try await API.shared.send("/api/security-question",value:["currentPassword":password,"question":prompt,"answer":response])
                case .recovery:
                    let result=try await API.shared.getMutation("/api/recovery-code",value:["currentPassword":password])
                    guard !Task.isCancelled,owner == store.state?.user.id else { return }
                    recoveryCode=result["recoveryCode"].string
                case .logoutAll: try await store.logoutAllDevices()
                }
                guard !Task.isCancelled,owner == store.state?.user.id else { return }
                newPassword=""; confirmation=""; message="تم حفظ التغيير بنجاح."
            } catch { if !Task.isCancelled { store.report(error); message=error.localizedDescription } }
        }
    }
}

enum SecurityInput {
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
