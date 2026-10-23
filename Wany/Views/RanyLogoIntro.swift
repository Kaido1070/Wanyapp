import SwiftUI

struct RanyLogoTimeline {
    static let revealAt=0.86
    static let travelEnd=1.58
    static let duration=1.68
    static func progress(_ elapsed: Double) -> Double {
        let p=min(1,max(0,(elapsed-revealAt)/(travelEnd-revealAt)))
        return p*p*(3-2*p)
    }
    static func frame(size: CGSize,origin: CGPoint,source: CGRect?,destination: CGRect?,elapsed: Double) -> CGRect {
        let start=source.map { CGRect(x:$0.minX-origin.x,y:$0.minY-origin.y,width:$0.width,height:$0.height) }
            ?? CGRect(x:size.width/2-64,y:size.height/2-64,width:128,height:128)
        let end=destination.map { CGRect(x:$0.midX-origin.x-$0.width/2,y:$0.midY-origin.y-$0.width/2,width:$0.width,height:$0.width) } ?? start
        let p=CGFloat(progress(elapsed))
        return CGRect(x:start.minX+(end.minX-start.minX)*p,y:start.minY+(end.minY-start.minY)*p,
                      width:start.width+(end.width-start.width)*p,height:start.height+(end.height-start.height)*p)
    }
}

// A single official mark: appear, one restrained lighting pass, measured handoff.
// Its clock starts in the active scene and never depends on covers or WebKit.
struct RanyLogoIntro: View {
    var destination: CGRect?
    var source: CGRect?
    // Morph into the circular navigation-bar mark while flying to the header.
    var roundTarget = false
    var onStart: (Date) -> Void = { _ in }
    var reduceMotionOverride: Bool? = nil
    let onReveal: () -> Void
    let onFinish: () -> Void
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    private var reduced: Bool { reduceMotionOverride ?? systemReduced }
    @State private var startedAt: Date?
    @State private var revealed=false
    @State private var finished=false
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval:1.0/60,paused:startedAt == nil || finished)) { context in
                let time=startedAt.map { max(0,context.date.timeIntervalSince($0)) } ?? 0
                let duration=reduced ? 0.22 : RanyLogoTimeline.duration
                let departure=reduced ? max(0,min(1,(time-0.12)/0.1)) : RanyLogoTimeline.progress(time)
                let frame=RanyLogoTimeline.frame(size:geometry.size,origin:geometry.frame(in:.global).origin,source:source,destination:destination,elapsed:reduced ? 0 : time)
                ZStack {
                    Theme.background.opacity(1-departure)
                    let light=min(1,max(0,(time-0.12)/0.72))
                    RanyMark(size:frame.width,shineProgress:reduced ? -1.5 : CGFloat(-1.5+3*light*light*(3-2*light)),roundness:roundTarget ? 0.25+0.25*CGFloat(departure) : 0.25)
                        .opacity(min(1,time/0.14) * (reduced || destination == nil ? 1-departure : 1))
                        .position(x:frame.midX,y:frame.midY)
                }
                .transaction { $0.animation=nil }
                .onChange(of:time,initial:true) { _,time in
                    if startedAt != nil && time >= (reduced ? 0.12 : RanyLogoTimeline.revealAt) { reveal() }
                    if startedAt != nil && time >= duration { finish() }
                }
            }
        }.ignoresSafeArea().environment(\.layoutDirection,.leftToRight).allowsHitTesting(false)
            .accessibilityElement(children:.ignore).accessibilityLabel(RanyIdentity.name)
            .accessibilityIdentifier("rany.logo.opening")
            .task(id:phase) {
                guard phase == .active else { if startedAt != nil { finish() }; return }
                guard startedAt == nil,!finished else { return }
                let date=Date(); startedAt=date; onStart(date)
                do { try await Task.sleep(for:.seconds(reduced ? 0.24 : RanyLogoTimeline.duration+0.12)) } catch { return }
                finish()
            }
    }
    private func reveal() { guard !revealed else { return }; revealed=true; onReveal() }
    private func finish() { guard !finished else { return }; reveal(); finished=true; onFinish() }
}

struct RanyLogoPreview: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var fixture=AppStore(startServices:false)
    @State private var ready=false
    @State private var replay=UUID()
    @State private var login=false
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if ready {
                RanyExperience().id(replay).environment(fixture).environment(fixture.downloads)
                    .environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark).tint(Theme.accent).disabled(true)
            }
        }
        .overlay(alignment:.topLeading) {
            Button("إغلاق",systemImage:"xmark") { dismiss() }.padding(12).background(.regularMaterial,in:Capsule()).padding(12)
        }
        .overlay(alignment:.bottom) {
            VStack(spacing:12) {
                Button("إعادة المعاينة",systemImage:"arrow.counterclockwise") { replay=UUID() }
                Toggle("شاشة تسجيل الدخول",isOn:$login).font(RanyTypography.font(.caption))
                    .onChange(of:login) { _,value in fixture.state=value ? nil : store.state; replay=UUID() }
            }.padding(14).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18)).padding(18)
        }
        .onAppear { fixture.online=false; login=store.state == nil; fixture.state=store.state; fixture.stories=store.stories; ready=true }
        .onChange(of:store.state?.user.id) { _,_ in dismiss() }
    }
}
