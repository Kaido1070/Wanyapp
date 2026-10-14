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
    static var display: String { "Wany · \(version) (\(build))" }
    static var releases: [ReleaseNote] {
        guard let url = Bundle.main.url(forResource:"Releases",withExtension:"json"),
              let data = try? Data(contentsOf:url),
              let notes = try? JSONDecoder().decode([ReleaseNote].self,from:data) else { return [] }
        return notes
    }
}
struct UpdatesView: View {
    var body: some View {
        List {
            Section("الإصدار المثبت") { LabeledContent("Wany",value:"\(AppVersion.version) · بناء \(AppVersion.build)") }
            ForEach(AppVersion.releases) { release in
                Section {
                    ForEach(release.changes,id:\.self) { change in Text(change).font(.subheadline).padding(.vertical,3) }
                } header: {
                    VStack(alignment:.leading,spacing:4) {
                        Text("\(release.version) · بناء \(release.build)").font(.headline)
                        Text(release.date).font(.caption)
                    }.textCase(nil)
                }
            }
        }.navigationTitle("سجل التحديثات")
    }
}
