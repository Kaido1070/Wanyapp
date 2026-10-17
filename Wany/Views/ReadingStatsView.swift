import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: AppStore
    private var stats: [String:JSONValue] { store.state?.stats ?? [:] }
    private let fields=[("storiesRead","القصص المقروءة"),("organicChapters","الفصول المقروءة"),("organicCompletedChapters","الفصول المكتملة"),("bulkChapters","فصول معلّمة يدويًا"),("activeDays","أيام القراءة"),("dailyAverage","المعدل اليومي"),("currentStreak","الاستمرارية الحالية"),("bestStreak","أفضل استمرارية"),("accountDays","عمر الحساب بالأيام")]
    var body: some View {
        WanyScroll {
            Text("إحصائيات القراءة").font(.largeTitle.bold()).frame(maxWidth:.infinity,alignment:.leading)
            if stats.isEmpty { EmptyState(icon:"chart.bar",title:"الإحصائيات غير متاحة حاليًا",detail:"تُعرض قيم الموقع الحقيقية عند اكتمال المزامنة.") }
            else {
                if store.state?.pending.isEmpty == false || store.state?.pendingOpens?.isEmpty == false { Text("يوجد تقدم محلي بانتظار المزامنة. تتحدث الإحصائيات بعد رفعه.").font(.caption).foregroundStyle(.orange) }
                metricGrid
                ForEach(ReadingMilestones.groups) { group in MilestoneGroupCard(group:group,value:stats[group.metric]?.number ?? 0) }
                ReadingCalendarView(recent:stats["recentDays"]?.array ?? [])
            }
            if let error=store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Button("تحديث الإحصائيات",systemImage:"arrow.clockwise") { Task { await store.refresh() } }.disabled(!store.online || store.syncing)
        }.navigationTitle("الإحصائيات").refreshable { await store.refresh() }
    }
    private var metricGrid: some View {
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
            ForEach(fields,id:\.0) { field in
                VStack(spacing:9) { Text((stats[field.0]?.number ?? 0).formatted(.number.precision(.fractionLength(0...1)))).font(.title2.bold()).foregroundStyle(Theme.accent); Text(field.1).font(.caption) }.frame(maxWidth:.infinity).card()
            }
        }
    }
}
private struct MilestoneGroupCard: View {
    let group: ReadingMilestoneGroup
    let value: Double
    var body: some View {
        let rank=group.rank(value:value)
        VStack(alignment:.leading,spacing:12) {
            HStack { Label(group.title,systemImage:"trophy").font(.headline); Spacer(); Text(rank.current?.label ?? "لم تُفتح رتبة بعد").font(.caption).foregroundStyle(Theme.accent) }
            if let next=rank.next {
                Text("الهدف القادم: \(next.label) · \(Int(next.threshold)) \(group.unit)").font(.subheadline)
                ProgressView(value:rank.progress).tint(Theme.accent)
                Text("المتبقي \(Int(max(0,next.threshold-value))) \(group.unit)").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("التروفيات والإنجازات") {
                VStack(alignment:.leading,spacing:14) {
                    ForEach(group.milestones) { milestone in
                        HStack(alignment:.top) {
                            Image(systemName:value >= milestone.threshold ? "trophy.fill" : "lock").foregroundStyle(value >= milestone.threshold ? Theme.accent : .secondary)
                            VStack(alignment:.leading,spacing:4) { Text(milestone.label).font(.subheadline); Text(milestone.description).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if value >= milestone.threshold { Image(systemName:"checkmark").foregroundStyle(Theme.accent) }
                        }.padding(.top,6)
                    }
                }
            }.font(.caption)
        }.card()
    }
}
private struct ReadingCalendarView: View {
    let recent: [JSONValue]
    @State private var selected: ReadingCalendarDay?
    private var days: [ReadingCalendarDay] { ReadingCalendar.days(recent:recent) }
    var body: some View {
        let padding=ReadingCalendar.leadingSlots(days.first?.date)
        let maximum=max(1,days.map(\.count).max() ?? 1)
        VStack(alignment:.leading,spacing:12) {
            Text("تقويم القراءة · آخر 30 يومًا").font(.headline)
            Text("بتوقيت الموقع UTC+3").font(.caption2).foregroundStyle(.secondary)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:5),count:7),spacing:5) {
                ForEach(["أحد","اثنين","ثلاثاء","أربعاء","خميس","جمعة","سبت"],id:\.self) { Text($0).font(.system(size:9)).foregroundStyle(.secondary) }
                ForEach(0..<padding,id:\.self) { _ in Color.clear.aspectRatio(1,contentMode:.fit) }
                ForEach(days) { day in
                    Button { selected=day } label: {
                        Text(String(Int(day.key.suffix(2)) ?? 0)).font(.caption2).monospacedDigit().foregroundStyle(day.count>0 ? Color.black : Color.secondary)
                            .frame(maxWidth:.infinity).aspectRatio(1,contentMode:.fit)
                            .background(day.count>0 ? Theme.accent.opacity(0.25+0.7*Double(day.count)/Double(maximum)) : Theme.surface,in:RoundedRectangle(cornerRadius:7))
                    }.buttonStyle(.plain).accessibilityLabel("\(day.key)، \(day.count) فصل")
                }
            }.environment(\.layoutDirection,.leftToRight)
            if let selected { Text("\(selected.key) · \(selected.count) فصل").font(.caption).foregroundStyle(.secondary) }
        }.card()
    }
}
