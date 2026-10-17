import SwiftUI
import UIKit
import Combine

// One retained Text for each R/A/N/Y. No font swap, random scrambling or falling letters.
struct RanyIntro: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let accountTransition: Bool
    let loginDestination: Bool
    var firstAccount = false
    var destinationFrame: CGRect?
    var sourceFrame: CGRect?
    var onArrange: () -> Void = {}
    let onReveal: () -> Void
    let onFinish: () -> Void
    @State private var stage = 0
    @State private var visible = false
    var body: some View {
        GeometryReader { geometry in
            let layout = RanyIntroLayout(size:geometry.size,origin:geometry.frame(in:.global).origin,destinationFrame:destinationFrame,sourceFrame:sourceFrame)
            ZStack {
                Theme.background.opacity(stage < 4 ? 0.6 : 0)
                // The exact same asset and rendering modifiers used by the final toolbar/login mark.
                RanyMark(size:stage < 4 ? (accountTransition && !firstAccount ? 92 : 168) : layout.destinationSize(login:loginDestination),illuminated:stage == 3)
                    .opacity(stage >= 3 ? 1 : 0)
                    .position(stage == 3 && accountTransition && !firstAccount ? layout.loginPoint : layout.point(index:0,stage:stage,login:loginDestination))
                if firstAccount {
                    VStack(spacing:9) {
                        Text("أهلًا بأول حكاية لك").font(.system(size:22,weight:.medium))
                        Text("مكتبتك الجديدة جاهزة").font(RanyTypography.font(.footnote)).foregroundStyle(.secondary)
                        Capsule().fill(Theme.accent.opacity(0.6)).frame(width:stage >= 3 ? 90 : 12,height:1).padding(.top,10)
                    }.position(x:geometry.size.width/2,y:geometry.size.height*0.44+145)
                        .opacity(stage == 3 ? 1 : 0).offset(y:stage >= 3 ? 0 : 10)
                }
                ForEach(Array(RanyIdentity.displayLetters.enumerated()),id:\.offset) { index,letter in
                    if letter != " " {
                        let keep = RanyIdentity.retainedIndices.contains(index)
                        let size: CGFloat = stage == 0 ? 38 : (stage == 1 ? 54 : (stage <= 3 ? 92.8 : (loginDestination ? 63.5 : 22)))
                        Text(String(letter)).font(.custom(RanyIdentity.fontName,size:54))
                            .foregroundStyle(RanyTypography.brandColor)
                            .scaleEffect(size/54)
                            .position(layout.point(index:index,stage:stage,login:loginDestination))
                            .opacity(opacity(index:index,keep:keep))
                    }
                }
            }.opacity(visible ? 1 : 0).accessibilityElement(children:.ignore).accessibilityLabel("Rany، اقرأ في أي وقت")
        }.ignoresSafeArea().environment(\.layoutDirection,.leftToRight).allowsHitTesting(false)
        .task {
            if accountTransition && !firstAccount {
                stage = 3; visible = true
                guard await wait(reduceMotion ? 0.06 : 0.76) else { return }
                onArrange()
                onReveal()
                withAnimation(.timingCurve(0.22,0.7,0.15,1,duration:reduceMotion ? 0.08 : 0.78)) { stage = 4 }
                guard await wait(reduceMotion ? 0.1 : 0.8) else { return }
                onFinish(); return
            }
            stage = reduceMotion ? 2 : 0
            withAnimation(.easeOut(duration:reduceMotion ? 0.08 : 0.3)) { visible = true }
            guard await wait(reduceMotion ? 0.1 : 0.65) else { return }
            onArrange()
            if (!accountTransition || firstAccount) && !reduceMotion {
                withAnimation(.timingCurve(0.22,0.72,0.2,1,duration:0.82)) { stage = 1 }
                guard await wait(0.86) else { return }
                withAnimation(.timingCurve(0.22,0.75,0.2,1,duration:0.66)) { stage = 2 }
                guard await wait(0.7) else { return }
            }
            withAnimation(.easeOut(duration:reduceMotion ? 0.05 : 0.42)) { stage = 3 }
            guard await wait(reduceMotion ? 0.05 : (firstAccount ? 1.1 : 0.86)) else { return }
            onReveal()
            withAnimation(.timingCurve(0.2,0.75,0.2,1,duration:reduceMotion ? 0.08 : 0.84)) { stage = 4 }
            guard await wait(reduceMotion ? 0.1 : 0.86) else { return }
            onFinish()
        }
    }
    private func opacity(index: Int, keep: Bool) -> Double {
        if stage == 0 { return 1 }
        if stage == 1 { return keep ? 1 : 0 }
        if stage == 2 { return index == 0 ? 1 : 0 }
        return 0
    }
    private func wait(_ seconds: Double) async -> Bool {
        do { try await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000)); return !Task.isCancelled } catch { return false }
    }
}

struct RanyIntroLayout {
    let size: CGSize
    let origin: CGPoint
    let destinationFrame: CGRect?
    let sourceFrame: CGRect?
    private func localCenter(_ frame: CGRect) -> CGPoint {
        CGPoint(x:frame.midX-origin.x,y:frame.midY-origin.y)
    }
    var loginPoint: CGPoint { sourceFrame.map(localCenter) ?? CGPoint(x:size.width/2,y:max(105,size.height*0.16)) }
    func destinationSize(login: Bool) -> CGFloat { destinationFrame?.width ?? (login ? 92 : 32) }

    private func width(_ c: Character, at points: CGFloat) -> CGFloat {
        let font = UIFont(name:RanyIdentity.fontName,size:points) ?? UIFont.systemFont(ofSize:points)
        return max(1,(String(c) as NSString).size(withAttributes:[.font:font]).width)
    }
    private func linePoint(_ indices: [Int], index: Int, points: CGFloat, y: CGFloat) -> CGPoint {
        let widths = indices.map { width(RanyIdentity.displayLetters[$0],at:points) }
        let total = widths.reduce(0,+), shrink = min(1,(size.width-60)/total)
        let position = indices.firstIndex(of:index) ?? 0
        let x = size.width/2-total*shrink/2+(widths.prefix(position).reduce(0,+)+widths[position]/2)*shrink
        return CGPoint(x:x,y:y)
    }
    func point(index: Int, stage: Int, login: Bool) -> CGPoint {
        let middle = size.height*0.44
        if stage == 0 {
            return linePoint(index < 4 ? Array(0..<4) : Array(5..<12),index:index,points:38,y:middle+(index < 4 ? -26 : 30))
        }
        if stage == 1 {
            if RanyIdentity.retainedIndices.contains(index) { return linePoint(RanyIdentity.retainedIndices,index:index,points:54,y:middle) }
            let target = index < 5 ? 0 : 5
            return linePoint(RanyIdentity.retainedIndices,index:target,points:54,y:middle)
        }
        if stage <= 3 { return CGPoint(x:size.width/2,y:middle) }
        if let destinationFrame { return localCenter(destinationFrame) }
        return CGPoint(x:login ? size.width/2 : size.width-46,y:login ? max(105,size.height*0.16) : 70)
    }
}

struct RanyExperience: View {
    var cinematicConfiguration: CinematicConfiguration = .production
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var ambience = RanyAmbience()
    @State private var markFrames: [String:CGRect] = [:]
    @State private var assembly: Double = 0
    @State private var opening = true
    @State private var revealed = false
    @State private var glassProgress: Double = 0
    var body: some View {
        ZStack {
            RanyBackdropHost(ambience:ambience,reading:store.readerActive,accountID:store.state?.user.id,assembly:assembly).frame(maxWidth:.infinity,maxHeight:.infinity).ignoresSafeArea()
            RootView().id(store.state?.user.id).environment(\.ranyGlassProgress,glassProgress).environment(\.ranyMeasureMarkFrames,opening || store.enteringAccount).environment(\.ranyMarkCovered,opening || store.enteringAccount).opacity((opening && !revealed) || (store.enteringAccount && !revealed) ? 0 : 1)
                .animation(.easeOut(duration:reduceMotion ? 0.05 : 0.42),value:revealed)
                .allowsHitTesting(!opening && !store.enteringAccount)
                .accessibilityHidden(opening || store.enteringAccount)
            if opening {
                if cinematicConfiguration.shouldPlay() && store.error == nil && !store.loginRequired {
                    CinematicIntro(configuration:cinematicConfiguration,state:store.state,stories:store.stories,destination:markFrames[store.state == nil ? "login" : "header"],onReveal:{ arrangeArtwork(); revealContent() },onFinish:{
                        opening=false; UserDefaults.standard.set(true,forKey:"rany.cinematic.approved.v2")
                    })
                } else {
                RanyIntro(accountTransition:false,loginDestination:store.state == nil,firstAccount:store.firstArrival,destinationFrame:markFrames[store.state == nil ? "login" : "header"],sourceFrame:markFrames["login"],onArrange:arrangeArtwork,onReveal:revealContent,onFinish:{ opening = false; if store.firstArrival { store.completeAccountArrival() } })
                }
            } else if store.enteringAccount {
                RanyIntro(accountTransition:true,loginDestination:false,firstAccount:store.firstArrival,destinationFrame:markFrames["header"],sourceFrame:markFrames["login"],onArrange:arrangeArtwork,onReveal:revealContent,onFinish:{ store.completeAccountArrival() })
            }
        }.font(RanyTypography.font(.body))
        .onPreferenceChange(RanyMarkFrameKey.self) { frames in
            guard opening || store.enteringAccount else { return }
            for (key,frame) in frames where frame.width > 0 && frame.height > 0 && markFrames[key] != frame {
                markFrames[key] = frame
            }
        }
        .task(id:store.state?.user.id) {
            await ambience.attach(state:store.state,stories:store.stories)
            ambience.prepare(state:store.state,stories:store.stories)
        }
        .onReceive(NotificationCenter.default.publisher(for:.ranySessionExpired)) { _ in if store.state != nil { store.loginRequired=true } }
        .onReceive(store.objectWillChange.debounce(for:.seconds(3),scheduler:RunLoop.main)) { _ in
            if !store.readerActive { ambience.prepare(state:store.state,stories:store.stories) }
        }
        .onChange(of:store.enteringAccount) { _,value in if value { revealed = false; assembly = 0; glassProgress = 0 } }
        .onChange(of:store.error) { _,error in if error != nil && cinematicConfiguration.shouldPlay() { opening=false; arrangeArtwork(); revealContent() } }
        .onChange(of:store.loginRequired) { _,needed in if needed && cinematicConfiguration.shouldPlay() { opening=false; arrangeArtwork(); revealContent() } }
        .onChange(of:phase) { _,value in
            if value == .background { ambience.activateWhileHidden(state:store.state,stories:store.stories) }
        }
    }
    private func revealContent() {
        revealed = true
        // The protected surface appears with the content; its blur builds afterward.
        withAnimation(reduceMotion ? nil : .easeInOut(duration:1.15).delay(0.18)) { glassProgress = 1 }
    }
    private func arrangeArtwork() {
        withAnimation(reduceMotion ? nil : .timingCurve(0.22,0.72,0.2,1,duration:1.25)) { assembly = 1 }
    }

}
