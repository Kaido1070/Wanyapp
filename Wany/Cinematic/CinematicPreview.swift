import SwiftUI

struct CinematicPreview: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var fixture=AppStore(startServices:false)
    @StateObject private var ambience=RanyAmbience()
    @State private var playing=true
    @State private var revealed=false
    @State private var frames: [String:CGRect] = [:]
    @State private var replay=UUID()
    @State private var duration=4.8
    @State private var loadingCovers=false
    @State private var anonymous=false
    private var login: Bool { anonymous || fixture.state == nil }
    var body: some View {
        ZStack {
            RanyBackdropHost(ambience:ambience,reading:false,accountID:fixture.state?.user.id,assembly:1).ignoresSafeArea()
            RootView().id(fixture.state?.user.id).environmentObject(fixture).environmentObject(fixture.downloads)
                .environment(\.ranyMeasureMarkFrames,playing).environment(\.ranyMarkCovered,playing)
                .disabled(true).opacity(revealed ? 1 : 0).accessibilityHidden(playing)
            if playing {
                CinematicIntro(configuration:CinematicConfiguration(duration:duration),state:login ? nil : fixture.state,stories:fixture.stories,
                    destination:frames[login ? "login" : "header"],onReveal:{ withAnimation(.easeOut(duration:0.8)) { revealed=true } },onFinish:{ playing=false; revealed=true })
                    .id(replay)
            }
        }
        .environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark).tint(Theme.accent)
        .onPreferenceChange(RanyMarkFrameKey.self) { if playing { frames=$0 } }
        .overlay(alignment:.topTrailing) { Button("إغلاق",systemImage:"xmark") { dismiss() }.padding(12).background(.regularMaterial,in:Capsule()).padding(12) }
        .overlay(alignment:.bottom) {
            if !playing {
                VStack(spacing:10) {
                    Text("معاينة للقراءة فقط · التشغيل التلقائي غير مفعل").font(.caption)
                    HStack {
                        Button("إعادة",systemImage:"arrow.counterclockwise") { restart() }.accessibilityIdentifier("cinematic.replay")
                        Picker("المدة",selection:$duration) { Text("4.8s").tag(4.8); Text("6s").tag(6.0); Text("8s").tag(8.0) }.pickerStyle(.segmented)
                    }
                    Toggle("معاينة شاشة الدخول",isOn:$anonymous).font(.caption).onChange(of:anonymous) { _,value in fixture.state=value ? nil : store.state }
                    Button(loadingCovers ? "تجهيز الأغلفة…" : "تجهيز أغلفة الاهتمامات للمشاهدة التالية") {
                        loadingCovers=true
                        Task { await CinematicCovers.prefetch(store:store); fixture.stories=store.stories; loadingCovers=false }
                    }.disabled(loadingCovers || !store.online).font(.caption)
                }.padding(14).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20)).padding(.horizontal,12).padding(.bottom,90)
            }
        }
        .onAppear { fixture.online=false; fixture.state=store.state; fixture.stories=store.stories }
        .onChange(of:store.state?.user.id) { _,_ in dismiss() }
    }
    private func restart() { frames=[:]; revealed=false; replay=UUID(); playing=true }
}
