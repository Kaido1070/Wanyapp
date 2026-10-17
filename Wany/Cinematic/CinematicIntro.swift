import SwiftUI
import UIKit

struct CinematicIntro: View {
    let configuration: CinematicConfiguration
    let state: AccountState?
    let stories: [String:Story]
    let destination: CGRect?
    var imagesOverride: [UIImage]? = nil
    let onReveal: () -> Void
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    @State private var images: [UIImage] = []
    @State private var imageOwner: String?
    @State private var started: Date?
    @State private var revealed=false
    @State private var finished=false
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval:1.0/60,paused:finished || started == nil)) { context in
                let elapsed=started.map { max(0,context.date.timeIntervalSince($0)) } ?? 0
                let t=reduced ? 4.8 : min(4.8,elapsed/configuration.seconds*4.8)
                let layout=CinematicLayout(size:geometry.size,origin:geometry.frame(in:.global).origin,destination:destination,configuration:configuration)
                CinematicFrame(t:t,layout:layout,images:state?.user.id == imageOwner ? images : [],reduced:reduced,configuration:configuration,onReady:begin)
                .onChange(of:t) { _,value in
                    if value >= 4 { reveal() }
                    if value >= 4.79 { finish() }
                }
            }
        }.ignoresSafeArea().environment(\.layoutDirection,.leftToRight).allowsHitTesting(false)
            .accessibilityElement(children:.ignore).accessibilityLabel("Read Any Time، Rany")
            .task {
                guard configuration.valid else { finish(); return }
                if reduced { reveal(); try? await Task.sleep(nanoseconds:180_000_000); finish(); return }
                if let imagesOverride { images=imagesOverride }
                else { images=await CinematicCovers.cached(state:state,stories:stories) }
                guard !Task.isCancelled,!finished else { return }
                imageOwner=state?.user.id
                if images.isEmpty { begin() }
                // Bound preparation too; the timeline starts only after the first GPU frame.
                try? await Task.sleep(nanoseconds:5_000_000_000)
                if !Task.isCancelled,started == nil { finish() }
            }
            .task(id:started) {
                guard started != nil else { return }
                try? await Task.sleep(nanoseconds:UInt64((configuration.seconds+0.4)*1_000_000_000))
                if !Task.isCancelled { finish() }
            }
            .onChange(of:state?.user.id) { _,_ in finish() }
            .onChange(of:phase) { _,value in if value != .active { finish() } }
            .onChange(of:reduced) { _,value in if value { finish() } }
    }
    private func begin() { guard started == nil,!finished else { return }; started=Date() }
    private func reveal() { guard !revealed else { return }; revealed=true; onReveal() }
    private func finish() { guard !finished else { return }; finished=true; reveal(); onFinish() }
}

private struct CinematicFrame: View {
    let t: Double
    let layout: CinematicLayout
    let images: [UIImage]
    let reduced: Bool
    let configuration: CinematicConfiguration
    let onReady: () -> Void
    var body: some View {
        ZStack { pages; Theme.background.opacity(backgroundOpacity(t)); letters; officialLogo; paperEdges }
    }
    @ViewBuilder private var pages: some View {
        if !reduced && !images.isEmpty {
            CinematicPages(images:images,time:t,lighting:configuration.lighting,speed:configuration.pageSpeed,onReady:onReady)
                .mask { Rectangle().scaleEffect(x:1,y:1-CinematicConfiguration.ease(t,3.05,3.4)) }
        }
    }
    private var letters: some View {
        ForEach(Array(configuration.displayTitle.enumerated()),id:\.offset) { index,letter in
            if letter != " " { CinematicLetter(index:index,letter:letter,t:t,layout:layout,configuration:configuration) }
        }
    }
    private var officialLogo: some View {
        RanyMark(size:layout.logoSize(t),illuminated:t>3.76 && t<3.95)
            .mask(alignment:.leading) { Rectangle().scaleEffect(x:CinematicConfiguration.p(t,3.4,3.76),y:1,anchor:.leading) }
            .position(layout.logoPoint(t))
    }
    @ViewBuilder private var paperEdges: some View {
        if !reduced {
            ForEach(0..<3,id:\.self) { pass in CinematicPaperEdge(pass:pass,t:t,size:layout.size) }
        }
    }
    private func backgroundOpacity(_ t: Double) -> Double {
        if reduced { return 0 }
        let opening=1-CinematicConfiguration.ease(t,0,0.65)
        let closing=CinematicConfiguration.ease(t,2.85,3.4)
        let handoff=1-CinematicConfiguration.ease(t,4,4.8)
        return max(opening*0.92,0.34+closing*0.66)*handoff
    }
}
private struct CinematicLetter: View {
    let index: Int
    let letter: Character
    let t: Double
    let layout: CinematicLayout
    let configuration: CinematicConfiguration
    private var visible: Bool { t >= 0.58 && (configuration.retained.contains(index) || t < 2.13) && (index == 0 || t < 3.14) }
    private var glyph: Text { Text(String(letter)).font(Font.custom(RanyIdentity.fontName,fixedSize:100)).foregroundColor(RanyTypography.brandColor) }
    var body: some View {
        glyph
            .fixedSize().mask {
                GeometryReader { box in
                    let cut=layout.cut(index:index,t:t)
                    Rectangle().frame(width:box.size.width*CGFloat(1-cut)).offset(x:box.size.width*CGFloat(cut))
                }
            }
            .scaleEffect(layout.scale(index:index,t:t))
            .position(layout.point(index:index,t:t))
            .opacity(visible ? 1 : 0)
            .mask(alignment:.leading) {
                if index == 0 && t >= 3.4 {
                    GeometryReader { box in
                        let edge: CGFloat=layout.size.width/2-84+168*CGFloat(CinematicConfiguration.p(t,3.4,3.76))
                        Rectangle().frame(width:max(0,box.size.width-edge)).offset(x:edge)
                    }
                } else { Rectangle() }
            }
    }
}
private struct CinematicPaperEdge: View {
    let pass: Int
    let t: Double
    let size: CGSize
    private var begin: Double { [1.10,1.58,2.70][pass] }
    var body: some View {
        if t>begin && t<begin+0.45 {
            let sweep=CinematicConfiguration.p(t,begin,begin+0.45)
            Rectangle().fill(Color(red:0.38,green:0.34,blue:0.27))
                .overlay(alignment:.trailing) { Rectangle().fill(Color(red:0.83,green:0.77,blue:0.65)).frame(width:1) }
                .frame(width:15,height:145).rotationEffect(.degrees(-14))
                .shadow(color:.black.opacity(0.7),radius:6,x:9,y:3)
                .position(x:-45+(size.width+90)*CGFloat(sweep),y:size.height*0.46)
        }
    }
}

struct CinematicLayout {
    let size: CGSize
    let origin: CGPoint
    let destination: CGRect?
    let configuration: CinematicConfiguration
    private var letters: [Character] { Array(configuration.displayTitle) }
    func width(_ index: Int) -> CGFloat {
        let font=UIFont(name:RanyIdentity.fontName,size:100) ?? .systemFont(ofSize:100)
        return (String(letters[index]) as NSString).size(withAttributes:[.font:font]).width
    }
    private var rows: [[Int]] { [Array(0..<4),Array(5..<letters.count)] }
    private var titleScale: CGFloat {
        min(0.46,(size.width-48)/max(1,rows.map { $0.reduce(CGFloat(0)) { $0+width($1) } }.max() ?? 1))
    }
    private var center: CGPoint { CGPoint(x:size.width/2,y:size.height*0.46) }
    private var finalPoint: CGPoint { destination.map { CGPoint(x:$0.midX-origin.x,y:$0.midY-origin.y) } ?? center }
    func logoPoint(_ t: Double) -> CGPoint {
        let p=CinematicConfiguration.ease(t,4,4.8)
        return CGPoint(x:CinematicConfiguration.mix(center.x,finalPoint.x,p),y:CinematicConfiguration.mix(center.y,finalPoint.y,p))
    }
    func logoSize(_ t: Double) -> CGFloat {
        CinematicConfiguration.mix(168,destination?.width ?? 168,CinematicConfiguration.ease(t,4,4.8))
    }
    func scale(index: Int,t: Double) -> CGFloat {
        let gathered=CinematicConfiguration.mix(titleScale,0.68,CinematicConfiguration.ease(t,2.0,2.3))
        return index == 0 ? CinematicConfiguration.mix(gathered,0.94,CinematicConfiguration.ease(t,3.02,3.16)) : (configuration.retained.contains(index) ? gathered : titleScale)
    }
    func point(index: Int,t: Double) -> CGPoint {
        let row=rows.first { $0.contains(index) } ?? [index]
        let prior=row.prefix { $0 != index }.reduce(CGFloat(0)) { $0+width($1) }
        let total=row.reduce(CGFloat(0)) { $0+width($1) }
        let initial=CGPoint(x:center.x+(prior+width(index)/2-total/2)*titleScale,y:center.y+(index<4 ? -31 : 31))
        guard let position=configuration.retained.firstIndex(of:index) else { return initial }
        let retainedWidth=configuration.retained.reduce(CGFloat(0)) { $0+width($1) }
        let prefix=configuration.retained.prefix(position).reduce(CGFloat(0)) { $0+width($1) }
        let target=CGPoint(x:center.x+(prefix+width(index)/2-retainedWidth/2)*0.68,y:center.y)
        let gather=CinematicConfiguration.ease(t,2.0,2.3)
        var result=CGPoint(x:CinematicConfiguration.mix(initial.x,target.x,gather),y:CinematicConfiguration.mix(initial.y,target.y,gather))
        if index == 0 {
            result.x=CinematicConfiguration.mix(result.x,center.x,CinematicConfiguration.ease(t,3.02,3.16))
        }
        return result
    }
    func cut(index: Int,t: Double) -> Double {
        if index == 0 { return 0 }
        if configuration.retained.contains(index) { return CinematicConfiguration.p(t,2.7+Double(configuration.retained.firstIndex(of:index) ?? 0)*0.035,3.02) }
        let row=index<4 ? 0 : 1
        let start=(row == 0 ? 1.1 : 1.58)+Double(row == 0 ? index : index-5)*0.045
        return CinematicConfiguration.p(t,start,start+0.18)
    }
}
