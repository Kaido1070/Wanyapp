import Foundation

struct ReadingMilestone: Identifiable {
    let id: String
    let threshold: Double
    let label: String
    let description: String
}
struct ReadingMilestoneGroup: Identifiable {
    let id: String
    let title: String
    let metric: String
    let unit: String
    let milestones: [ReadingMilestone]
    func rank(value: Double) -> (current: ReadingMilestone?,next: ReadingMilestone?,progress: Double) {
        let current=milestones.last { value >= $0.threshold }, next=milestones.first { value < $0.threshold }
        let previous=current?.threshold ?? 0
        let progress=next.map { min(1,max(0,(value-previous)/max(1,$0.threshold-previous))) } ?? 1
        return (current,next,progress)
    }
}
enum ReadingMilestones {
    static let groups: [ReadingMilestoneGroup] = {
        guard let url=Bundle.main.url(forResource:"ReadingMilestones",withExtension:"json"),let data=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(JSONValue.self,from:data) else { return [] }
        let definitions=[("chapters","إنجازات الفصول","organicCompletedChapters","فصل","CHAPTER_TROPHIES"),("stories","إنجازات القصص","storiesRead","قصة","STORY_TROPHIES"),("streak","إنجازات الاستمرارية","bestStreak","يوم","STREAK_TROPHIES")]
        return definitions.map { category,title,metric,unit,key in
            ReadingMilestoneGroup(id:category,title:title,metric:metric,unit:unit,milestones:value[key].array.compactMap { row in
                let cells=row.array; guard cells.count==3,cells[0].number>0 else { return nil }
                return ReadingMilestone(id:category+"-"+String(cells[0].number),threshold:cells[0].number,label:cells[1].string,description:cells[2].string)
            })
        }
    }()
}
struct ReadingCalendarDay: Identifiable {
    let key: String
    let date: Date
    let count: Int
    var id: String { key }
}
enum ReadingCalendar {
    static func days(recent: [JSONValue],now: Date = Date()) -> [ReadingCalendarDay] {
        var calendar=Calendar(identifier:.gregorian); calendar.timeZone=TimeZone(secondsFromGMT:10800)!
        let today=calendar.startOfDay(for:now)
        let formatter=DateFormatter(); formatter.locale=Locale(identifier:"en_US_POSIX"); formatter.timeZone=calendar.timeZone; formatter.dateFormat="yyyy-MM-dd"
        let counts=Dictionary(recent.map { ($0["day"].string,Int($0["chapters"].number)) },uniquingKeysWith:{ a,b in max(a,b) })
        return (0..<30).compactMap { index in
            guard let date=calendar.date(byAdding:.day,value:index-29,to:today) else { return nil }
            let key=formatter.string(from:date)
            return ReadingCalendarDay(key:key,date:date,count:counts[key] ?? 0)
        }
    }
    static func leadingSlots(_ first: Date?) -> Int {
        guard let first else { return 0 }
        var calendar=Calendar(identifier:.gregorian); calendar.timeZone=TimeZone(secondsFromGMT:10800)!
        return calendar.component(.weekday,from:first)-1
    }
    // Sunday-first weeks of exactly seven slots; empty slots pad the first and last week.
    static func weeks(_ days: [ReadingCalendarDay]) -> [[ReadingCalendarDay?]] {
        let cells=Array(repeating:nil,count:leadingSlots(days.first?.date))+days.map { Optional($0) }
        return stride(from:0,to:cells.count,by:7).map { start in
            let week=Array(cells[start..<min(start+7,cells.count)])
            return week+Array(repeating:nil,count:7-week.count)
        }
    }
}
