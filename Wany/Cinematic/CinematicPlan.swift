import Foundation
import CoreGraphics

struct CinematicConfiguration {
    enum Playback: Equatable { case disabled, coldLaunch, once }
    static let production = CinematicConfiguration(playback:.disabled)
    var playback: Playback = .disabled
    var duration: Double = 4.8
    var fullBrandName = "Read Any Time"
    // Mathematical script glyphs from the approved identity, with the requested word spacing.
    var displayTitle = "𝓡𝓔𝓐𝓓 𝓐𝓝𝓨 𝓣𝓘𝓜𝓔"
    var retained = [0,5,6,7]
    var lighting: Double = 1
    var pageSpeed: Double = 1
    var forceReducedMotion = false
    var seconds: Double { duration.isFinite ? min(12,max(3.8,duration)) : 4.8 }
    func shouldPlay(_ defaults: UserDefaults = .standard) -> Bool {
        playback == .coldLaunch || (playback == .once && !defaults.bool(forKey:"rany.cinematic.approved.v2"))
    }
    static func p(_ t: Double,_ a: Double,_ b: Double) -> Double { min(1,max(0,(t-a)/max(0.001,b-a))) }
    static func ease(_ t: Double,_ a: Double,_ b: Double) -> Double { let x=p(t,a,b); return x*x*(3-2*x) }
    static func mix(_ a: CGFloat,_ b: CGFloat,_ p: Double) -> CGFloat { a+(b-a)*CGFloat(p) }
    var valid: Bool {
        let chars=Array(displayTitle)
        return retained.count == 4 && retained.allSatisfy { chars.indices.contains($0) }
            && retained.map { String(chars[$0]) }.joined() == RanyIdentity.displayName
    }
}

enum CinematicCoverPlan {
    static let limit = 8
    static func keys(data: AccountData,stories: [String:Story],interests: [String],popular: [String]) -> [String] {
        var scores: [String:Double] = [:], genres: [String:Double] = [:]
        for (index,key) in interests.prefix(80).enumerated() { scores[key,default:0] += 30+Double(80-index)/8 }
        for key in data.favorites { scores[key,default:0] += 45 }
        let reading = data.library.sorted { ($0.lastReadAt ?? $0.updatedAt) > ($1.lastReadAt ?? $1.updatedAt) }
        for (index,entry) in reading.enumerated() {
            scores[entry.mangaId,default:0] += (entry.status == "reading" ? 70 : 20)+Double(max(0,30-index))
        }
        for record in data.progress.values { scores[record.mangaId,default:0] += min(8,record.percent/25) }
        for (key,score) in scores {
            for genre in stories[key]?.genres ?? [] { genres[genre.lowercased(),default:0] += score }
        }
        let weight = max(1,genres.values.max() ?? 1)
        for (index,key) in popular.enumerated() {
            let affinity = (stories[key]?.genres ?? []).reduce(0.0) { $0+(genres[$1.lowercased()] ?? 0)/weight }
            scores[key,default:0] += 10+min(30,affinity*8)+Double(max(0,30-index))/100
        }
        // Stable keys, never a made-up global popularity score. Popular order is source-owned.
        return scores.keys.filter { !(stories[$0]?.cover.isEmpty ?? true) }.sorted {
            let a=scores[$0] ?? 0,b=scores[$1] ?? 0
            return a == b ? $0 < $1 : a > b
        }
    }
}
