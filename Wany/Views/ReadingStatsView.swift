import SwiftUI

struct StatsView: View {
    @Environment(AppStore.self) private var store
    private var stats: [String:JSONValue] { store.state?.stats ?? [:] }
    var body: some View {
        WanyScroll {
            if stats.isEmpty { EmptyState(icon:"chart.bar",title:"الإحصائيات غير متاحة حاليًا",detail:"تُعرض قيم الموقع الحقيقية عند اكتمال المزامنة.") }
            else {
                if store.state?.pending.isEmpty == false || store.state?.pendingOpens?.isEmpty == false { Text("يوجد تقدم محلي بانتظار المزامنة. تتحدث الإحصائيات بعد رفعه.").font(.caption).foregroundStyle(.orange) }
                overview
                detailTiles
                ForEach(ReadingMilestones.groups) { group in MilestoneGroupCard(group:group,value:stats[group.metric]?.number ?? 0) }
                ReadingCalendarView(recent:stats["recentDays"]?.array ?? [])
            }
            if let error=store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Button("تحديث الإحصائيات",systemImage:"arrow.clockwise") { Task { await store.refresh() } }.disabled(!store.online || store.syncing)
        }.navigationTitle("إحصائيات القراءة").navigationBarTitleDisplayMode(.inline).refreshable { await store.refresh() }
    }
    private func value(_ key: String) -> Double { stats[key]?.number ?? 0 }
    private func number(_ key: String) -> String { value(key).formatted(.number.precision(.fractionLength(0...1))) }
    // One headline number carries the page; the rest supports it.
    private var overview: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.firstTextBaseline,spacing:10) {
                Text(number("organicChapters")).font(.system(.largeTitle,design:.rounded).weight(.heavy)).monospacedDigit()
                    .foregroundStyle(Theme.accent).lineLimit(1).minimumScaleFactor(0.6)
                Text("فصل مقروء").font(.headline).foregroundStyle(.secondary)
            }
            Text("\(number("storiesRead")) قصة · \(number("activeDays")) يوم قراءة · عمر الحساب \(number("accountDays")) يوم")
                .font(.subheadline).foregroundStyle(.secondary)
            Divider()
            HStack(spacing:12) {
                streak("flame.fill",title:"الاستمرارية الحالية",value:number("currentStreak"))
                Divider().frame(height:40)
                streak("trophy.fill",title:"أفضل استمرارية",value:number("bestStreak"))
            }
        }.frame(maxWidth:.infinity,alignment:.leading).card()
    }
    private func streak(_ icon: String,title: String,value: String) -> some View {
        HStack(spacing:10) {
            Image(systemName:icon).font(.title3).foregroundStyle(Theme.accent).frame(width:28)
            VStack(alignment:.leading,spacing:2) {
                Text("\(value) يوم").font(.system(.title3,design:.rounded).weight(.bold)).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
    private var detailTiles: some View {
        let tiles=[("organicCompletedChapters","فصل مكتمل","checkmark.circle"),("bulkChapters","معلّم يدويًا","hand.tap"),("dailyAverage","المعدل اليومي","chart.line.uptrend.xyaxis")]
        return LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10,alignment:.top),count:3),spacing:10) {
            ForEach(tiles,id:\.0) { tile in
                VStack(alignment:.leading,spacing:6) {
                    Image(systemName:tile.2).font(.subheadline).foregroundStyle(Theme.accent)
                    Text(number(tile.0)).font(.system(.title3,design:.rounded).weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(tile.1).font(.caption2).foregroundStyle(.secondary).lineLimit(2,reservesSpace:true)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(12).ranyGlass(radius:16)
                    .accessibilityElement(children:.combine)
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
    private let weekdays=["أحد","اثنين","ثلاثاء","أربعاء","خميس","جمعة","سبت"]
    var body: some View {
        let weeks=ReadingCalendar.weeks(days)
        let maximum=max(1,days.map(\.count).max() ?? 1)
        VStack(alignment:.leading,spacing:12) {
            Text("تقويم القراءة · آخر 30 يومًا").font(.headline)
            Text("بتوقيت الموقع UTC+3").font(.caption2).foregroundStyle(.secondary)
            // Right-to-left like an Arabic calendar: the week starts at the right edge.
            VStack(spacing:4) {
                HStack(spacing:4) {
                    ForEach(weekdays,id:\.self) { Text($0).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth:.infinity) }
                }
                ForEach(weeks.indices,id:\.self) { row in
                    HStack(spacing:4) {
                        ForEach(0..<7,id:\.self) { column in cell(weeks[row][column],maximum:maximum) }
                    }
                }
            }
            if let selected { Text("\(selected.key) · \(selected.count) فصل").font(.caption).foregroundStyle(.secondary) }
        }.card()
    }
    @ViewBuilder private func cell(_ day: ReadingCalendarDay?,maximum: Int) -> some View {
        if let day {
            Button { selected=day } label: {
                Text(String(Int(day.key.suffix(2)) ?? 0)).font(.caption).monospacedDigit().foregroundStyle(day.count>0 ? Color.black : Color.secondary)
                    .frame(width:34,height:34)
                    .background(day.count>0 ? Theme.accent.opacity(0.25+0.7*Double(day.count)/Double(maximum)) : Theme.surface,in:Circle())
                    .overlay { if selected?.id == day.id { Circle().stroke(Theme.accent,lineWidth:2) } }
                    .frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(day.key)، \(day.count) فصل")
        } else {
            Color.clear.frame(maxWidth:.infinity,minHeight:44)
        }
    }
}
