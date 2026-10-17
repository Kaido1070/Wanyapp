import SwiftUI

struct RanyProgressStatus: View {
    @EnvironmentObject var store: AppStore
    private var status: RanyProgressState {
        RanyProgressState.resolve(locallySaved:!store.localSaveFailed,
            confirmed:store.state?.lastSynced != nil,
            pending:!(store.state?.pending.isEmpty ?? true) || !(store.state?.completedPending?.isEmpty ?? true),
            syncing:store.syncing,sessionValid:!store.loginRequired)
    }
    var body: some View {
        HStack(spacing:7) {
            Image(systemName:status.icon)
            Text(status.label).font(.caption)
            Spacer(minLength:0)
            Button { Task { await store.refresh() } } label: {
                Image(systemName:"arrow.clockwise").frame(width:44,height:32).contentShape(Rectangle())
            }.disabled(!store.online || store.syncing).accessibilityLabel("مزامنة تقدم القراءة")
        }.foregroundStyle(status == .saveFailed ? Color.orange : Color.secondary)
            .accessibilityIdentifier("profile.progress-status")
    }
}

struct ProfileEditView: View {
    @EnvironmentObject var store: AppStore
    @State private var name = ""
    @State private var busy = false
    var body: some View {
        WanyScroll {
            VStack(alignment:.leading,spacing:16) {
                Text("الاسم الظاهر").font(.headline)
                TextField("اسمك",text:$name).textContentType(.name).textFieldStyle(.roundedBorder)
                Button {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            try await API.shared.send("/api/profile/name",method:"PUT",value:["name":name.trimmingCharacters(in:.whitespacesAndNewlines)])
                            await store.refresh()
                        } catch { if !isRequestCancellation(error) { store.error = error.localizedDescription } }
                    }
                } label: { HStack { if busy { ProgressView() }; Text("حفظ الاسم") }.frame(maxWidth:.infinity,minHeight:44) }
                    .disabled(!store.online || busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }.card()
            WanyLink { AvatarPickerView() } label: {
                HStack { Label("تعديل الصورة الشخصية",systemImage:"person.crop.circle"); Spacer(); Image(systemName:"chevron.left") }.frame(minHeight:44).card()
            }
        }.navigationTitle("تعديل الملف الشخصي").onAppear { name = store.state?.user.name ?? "" }
    }
}
