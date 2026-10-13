import SwiftUI

struct DownloadSummary: View {
    @EnvironmentObject var downloads: Downloads
    let job: DownloadJob
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Label(job.complete ? "مكتمل" : job.paused ? "متوقف مؤقتًا" : "\(job.completedChapters) فصل مكتمل",systemImage:job.complete ? "checkmark.circle.fill" : "arrow.down.circle"); Spacer(); Text("متبقي \(job.remainingChapters)").foregroundStyle(.secondary) }.font(.subheadline)
            HStack(alignment:.firstTextBaseline) {
                Text(byteLabel(job.bytes)).font(.title3.bold()).monospacedDigit()
                Text("/ " + (job.total.map(byteLabel) ?? "جارٍ حساب الحجم الإجمالي")).font(.caption).foregroundStyle(.secondary)
            }.environment(\.layoutDirection,.leftToRight).frame(maxWidth:.infinity,alignment:.leading)
            HStack {
                Text("\(job.chapters.count) فصل • \(job.chapters.flatMap(\.images).filter(\.done).count) صورة محفوظة").font(.caption)
                Spacer()
                Text(job.paused || job.complete || !downloads.online ? "0 B/s" : byteLabel(downloads.speedFor(job.id))+"/s").font(.caption.monospacedDigit()).foregroundStyle(Theme.accent)
            }
            if let error = job.error { Text(error).font(.caption).foregroundStyle(.orange) }
            let failures = job.chapters.filter { $0.error != nil || $0.images.contains(where:{$0.failure != nil}) }.count
            if failures > 0 { Text("\(failures) فصل يحتوي على صور ناقصة أو تعذر تجهيزه").font(.caption).foregroundStyle(.orange) }
            if !job.complete {
                HStack {
                    Button { if job.paused { downloads.retry(job.id) } else { downloads.pause(job.id) } } label: { Label(job.paused ? "استكمال" : "إيقاف مؤقت",systemImage:job.paused ? "play.fill" : "pause.fill") }
                    Spacer()
                    Button("إعادة تحميل الناقص") { downloads.retry(job.id) }
                }.font(.caption).buttonStyle(.bordered)
            }
        }
    }
}
struct DownloadsView: View {
    @EnvironmentObject var downloads: Downloads
    @State private var removing: String?
    @State private var filter = "الكل"
    var body: some View {
        WanyScroll {
            HStack { Text("تنزيلاتي").font(.largeTitle.bold()); Spacer(); Text(byteLabel(downloads.jobs.reduce(0){$0+$1.bytes})).font(.caption).foregroundStyle(.secondary) }
            Picker("التنزيلات",selection:$filter) { Text("الكل").tag("الكل"); Text("مكتمل").tag("مكتمل"); Text("غير مكتمل").tag("غير مكتمل") }.pickerStyle(.segmented)
            if downloads.jobs.isEmpty { EmptyState(icon:"arrow.down.circle",title:"مكتبتك بدون إنترنت",detail:"افتح قصة واضغط تحميل القصة كاملة، أو حمّل الفصول التي تختارها.") }
            ForEach(downloads.jobs.filter { filter == "الكل" || (filter == "مكتمل" ? $0.complete : !$0.complete) }) { job in
                VStack(alignment:.leading,spacing:15) {
                    HStack {
                        NavigationLink { StoryView(initial:job.story) } label: {
                            HStack { CoverView(story:job.story).frame(width:58,height:82).clipShape(RoundedRectangle(cornerRadius:9)); VStack(alignment:.leading,spacing:6) { Text(job.story.title).bold().lineLimit(2); Text(job.wholeStory ? "القصة كاملة" : "فصول محددة").font(.caption).foregroundStyle(.secondary) } }.foregroundStyle(.primary)
                        }
                        Spacer(); Button(role:.destructive) { removing = job.id } label: { Image(systemName:"trash") }
                    }
                    DownloadSummary(job:job)
                }.card()
            }
        }.navigationTitle("التنزيلات")
        .confirmationDialog("حذف الصور المحملة؟ سيبقى تقدم القراءة محفوظًا.",isPresented:Binding(get:{removing != nil},set:{if !$0 { removing = nil }})) { Button("حذف التنزيل",role:.destructive) { if let removing { downloads.remove(removing) }; removing = nil } }
    }
}
