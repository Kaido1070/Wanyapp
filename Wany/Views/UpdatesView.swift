import SwiftUI

struct ReleaseNote: Decodable, Identifiable {
    let version: String
    let build: Int
    let date: String
    let changes: [String]
    var id: String { version }
}
enum AppVersion {
    static var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "غير معروف" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "غير معروف" }
    static var display: String { "Rany · \(version) (\(build))" }
    static var releases: [ReleaseNote] {
        guard let url = Bundle.main.url(forResource:"Releases",withExtension:"json"),
              let data = try? Data(contentsOf:url),
              let notes = try? JSONDecoder().decode([ReleaseNote].self,from:data) else { return [] }
        return notes
    }
}
struct UpdatesView: View {
    @State private var cinematicPreview=false
    var body: some View {
        List {
            Section("الإصدار المثبت") { LabeledContent("Rany",value:"\(AppVersion.version) · بناء \(AppVersion.build)").listRowBackground(Theme.surface.opacity(0.25)) }
            Section("معاينة الافتتاحية") {
                Button("معاينة علامة البداية",systemImage:"play.rectangle") { cinematicPreview=true }
                    .accessibilityIdentifier("cinematic.open-preview").listRowBackground(Theme.surface.opacity(0.25))
            }
            ForEach(AppVersion.releases) { release in
                Section {
                    ForEach(release.changes,id:\.self) { change in Text(change).font(RanyTypography.font(.subheadline)).padding(.vertical,3).listRowBackground(Theme.surface.opacity(0.25)) }
                } header: {
                    VStack(alignment:.leading,spacing:4) {
                        Text("\(release.version) · بناء \(release.build)").font(RanyTypography.font(.headline))
                        Text(release.date).font(RanyTypography.font(.caption))
                    }.textCase(nil)
                }
            }
        }.scrollContentBackground(.hidden).ranyClearNavigation().navigationTitle("سجل التحديثات")
        .fullScreenCover(isPresented:$cinematicPreview) { RanyLogoPreview() }
    }
}
