import SwiftUI
import UIKit
import ImageIO
import Combine

private struct RanyBackdropEntry: Codable, Sendable {
    let key: String
    let cover: String
    let file: String
}
private struct RanyBackdropManifest: Codable, Sendable { let entries: [RanyBackdropEntry]; let qualityVersion: Int }

@MainActor final class RanyAmbience: ObservableObject {
    @Published private(set) var images: [UIImage] = RanyAmbience.defaults()
    private var owner: String?
    private var generation = UUID()
    private var task: Task<Void,Never>?
    private var fingerprint = ""
    private var activeFiles: [String] = []
    private static func defaults() -> [UIImage] { (1...14).compactMap { UIImage(named:"RanyDefault\($0)") } }
    func displayImages(accountID: String?) -> [UIImage] { accountID == owner ? images : Self.defaults() }
    nonisolated private static func completePool(_ primary: [UIImage], defaults: [UIImage]) -> [UIImage] {
        var result: [UIImage] = [], signatures: [UInt64] = []
        for image in primary+defaults {
            guard result.count < RanyIdentity.maxBackdropCovers else { break }
            guard let cg = image.cgImage, let hash = RanyCoverQuality.signature(cg), !signatures.contains(where:{ RanyCoverQuality.matches($0,hash) }) else { continue }
            signatures.append(hash); result.append(image)
        }
        return result
    }
    func attach(state: AccountState?, stories: [String:Story]) async {
        guard owner != state?.user.id else { return }
        task?.cancel(); generation = UUID(); owner = state?.user.id; fingerprint = ""; activeFiles = []
        // Never leave the preceding account's artwork on screen, even for one decoded frame.
        images = Self.defaults()
        guard let state else { return }
        let allowed = RanyBackdropPlan.candidates(data:state.data,stories:stories)
        let folder = Disk.folder(state.user.id), token = generation, fallback = Self.defaults()
        let prepared = await Task.detached(priority:.utility) {
            let entries = Self.readPrepared(folder:folder,allowed:allowed)
            return (entries,Self.completePool(entries.map(\.1),defaults:fallback))
        }.value
        let entries = prepared.0
        guard generation == token, !Task.isCancelled else { return }
        images = prepared.1; activeFiles = entries.map { $0.0.file }
    }

    func prepare(state: AccountState?, stories: [String:Story]) {
        guard let state, owner == state.user.id else { return }
        let candidates = RanyBackdropPlan.candidates(data:state.data,stories:stories)
        let sources = candidates.map { ($0,Disk.file(state.user.id,Disk.coverName($0.key))) }
        let stamp = sources.map { entry,url in entry.key+entry.cover+((try? FileManager.default.attributesOfItem(atPath:url.path)[.modificationDate] as? Date)?.description ?? "missing") }.joined(separator:"|")
        guard stamp != fingerprint else { return }
        task?.cancel(); let token = generation, folder = Disk.folder(state.user.id), keep = activeFiles
        task = Task { [weak self] in
            let worker = Task.detached(priority:.utility) { Self.stage(folder:folder,sources:sources,keep:keep) }
            let success = await withTaskCancellationHandler(operation:{ await worker.value },onCancel:{ worker.cancel() })
            guard let self, self.generation == token, !Task.isCancelled else { return }
            if success { self.fingerprint = stamp }
            self.task = nil
            // Preparation only stages files. Visible UIImage identities remain unchanged.
        }
    }
    func activateWhileHidden(state: AccountState?, stories: [String:Story]) {
        guard let state, owner == state.user.id else { return }
        let folder = Disk.folder(state.user.id), allowed = RanyBackdropPlan.candidates(data:state.data,stories:stories), token = generation, fallback = Self.defaults()
        Task {
            let prepared = await Task.detached(priority:.utility) {
                let entries = Self.readPrepared(folder:folder,allowed:allowed)
                return (entries,Self.completePool(entries.map(\.1),defaults:fallback))
            }.value
            let entries = prepared.0
            guard generation == token, UIApplication.shared.applicationState == .background else { return }
            images = prepared.1
            activeFiles = entries.map { $0.0.file }
        }
    }
    nonisolated private static func readPrepared(folder: URL, allowed: [RanyBackdropCandidate]) -> [(RanyBackdropEntry,UIImage)] {
        guard let bytes = try? Data(contentsOf:folder.appendingPathComponent("ambience/pending.json")), let manifest = try? JSONDecoder().decode(RanyBackdropManifest.self,from:bytes), manifest.qualityVersion == 3 else { return [] }
        let allowedSet = Set(allowed)
        return manifest.entries.prefix(RanyIdentity.maxBackdropCovers).compactMap { entry in
            guard allowedSet.contains(RanyBackdropCandidate(key:entry.key,cover:entry.cover)), let image = thumbnail(folder.appendingPathComponent("ambience/"+entry.file)) else { return nil }
            return (entry,image)
        }
    }
    nonisolated private static func thumbnail(_ url: URL, validateSource: Bool = false) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,nil), CGImageSourceGetStatus(source) == .statusComplete else { return nil }
        if validateSource {
            guard let info = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
                  let width = info[kCGImagePropertyPixelWidth] as? Int, let height = info[kCGImagePropertyPixelHeight] as? Int,
                  RanyCoverQuality.acceptsDimensions(width:width,height:height) else { return nil }
        }
        guard
              let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:240,kCGImageSourceShouldCacheImmediately:true] as CFDictionary), cg.width >= 32, cg.height >= 32 else { return nil }
        if validateSource && !RanyCoverQuality.hasDetail(cg) { return nil }
        let image = UIImage(cgImage:cg), size = CGSize(width:180,height:248)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size:size,format:format).image { context in
            UIColor(red:0.09,green:0.10,blue:0.11,alpha:1).setFill(); context.fill(CGRect(origin:.zero,size:size))
            let scale = max(size.width/image.size.width,size.height/image.size.height)
            let scaled = CGSize(width:image.size.width*scale,height:image.size.height*scale)
            image.draw(in:CGRect(x:(size.width-scaled.width)/2,y:(size.height-scaled.height)/2,width:scaled.width,height:scaled.height))
        }
    }
    nonisolated private static func stage(folder: URL, sources: [(RanyBackdropCandidate,URL)], keep: [String]) -> Bool {
        let target = folder.appendingPathComponent("ambience",isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true)
            var entries: [RanyBackdropEntry] = []
            var signatures: [UInt64] = []
            for (candidate,source) in sources.prefix(RanyIdentity.maxBackdropCandidates) {
                if entries.count == RanyIdentity.maxBackdropCovers { break }
                guard !Task.isCancelled else { return false }
                guard let image = thumbnail(source,validateSource:true), let bytes = image.jpegData(compressionQuality:0.85) else { continue }
                guard let cg = image.cgImage, let hash = RanyCoverQuality.signature(cg), !signatures.contains(where:{ RanyCoverQuality.matches($0,hash) }) else { continue }
                signatures.append(hash)
                let file = Disk.hash(candidate.key+"|"+candidate.cover)+".jpg"
                try bytes.write(to:target.appendingPathComponent(file),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
                entries.append(RanyBackdropEntry(key:candidate.key,cover:candidate.cover,file:file))
            }
            guard !Task.isCancelled else { return false }
            let bytes = try JSONEncoder().encode(RanyBackdropManifest(entries:entries,qualityVersion:3))
            try bytes.write(to:target.appendingPathComponent("pending.json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            let retained = Set(keep+entries.map(\.file))
            for url in (try? FileManager.default.contentsOfDirectory(at:target,includingPropertiesForKeys:nil)) ?? [] where url.pathExtension == "jpg" && !retained.contains(url.lastPathComponent) { try? FileManager.default.removeItem(at:url) }
            return true
        } catch { return false } // Optional ambience must never interrupt reading or show an alert.
    }
}

struct RanyBackdrop: View {
    @ObservedObject var ambience: RanyAmbience
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var reading = false
    var accountID: String?
    var assembly: Double = 1
    var held = false
    @AppStorage(RanyAppearanceKeys.background) private var enabled = true
    @State private var elapsed: TimeInterval = 0
    @State private var resumedAt = Date()
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    // Scrolling and page transitions freeze the circuit in place; it resumes from the same position.
    private var paused: Bool { !enabled || reading || held || scenePhase != .active || reduceMotion || reduceTransparency || lowPower }
    var body: some View {
        let visibleImages = ambience.displayImages(accountID:accountID)
        ZStack {
            Theme.background
            if enabled && !reading && !reduceTransparency {
                TimelineView(.animation(minimumInterval:1.0/24.0,paused:paused)) { timeline in
                    RanyBackdropArtwork(images:visibleImages,time:elapsed + (paused ? 0 : max(0,timeline.date.timeIntervalSince(resumedAt))),assembly:reduceMotion || lowPower ? 1 : assembly)

                }
                RadialGradient(colors:[Theme.background.opacity(0.74),Theme.background.opacity(0.22),.clear],center:.center,startRadius:15,endRadius:460)
                LinearGradient(colors:[Theme.background.opacity(0.12),.clear,Theme.background.opacity(0.36)],startPoint:.top,endPoint:.bottom)
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
        .onChange(of:paused) { _,value in
            if value { elapsed += max(0,Date().timeIntervalSince(resumedAt)) }
            else { resumedAt = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for:.NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
}


private struct RanyBackdropArtwork: View, Animatable {
    let images: [UIImage]
    let time: TimeInterval
    var assembly: Double
    var animatableData: Double { get { assembly } set { assembly = newValue } }
    var body: some View {
        Canvas(opaque:false,rendersAsynchronously:true) { context,size in
            let order = CGFloat(min(1,max(0,assembly)))
            let width = min(min(size.width*0.30,size.height*0.15),190), height = width*248/180
            for (i,image) in images.prefix(RanyIdentity.maxBackdropCovers).enumerated() {
                let target = RanyBackdropMotion.position(index:i,elapsed:time,height:Double(size.height))
                let scattered = RanyBackdropMotion.scatteredPosition(index:i)
                let x = size.width*(scattered.x+(target.x-scattered.x)*order)
                let y = size.height*(scattered.y+(target.y-scattered.y)*order)
                guard y > -height && y < size.height+height else { continue }
                var layer = context; layer.opacity = 0.25+Double(order)*0.11
                layer.translateBy(x:x,y:y)
                let initialAngle = Double((i*23)%35)-17
                layer.rotate(by:.degrees(initialAngle+(RanyBackdropMotion.angle(index:i)-initialAngle)*Double(order)))
                let scale = 0.88+0.12*order; layer.scaleBy(x:scale,y:scale)
                layer.clip(to:Path(roundedRect:CGRect(x:-width/2,y:-height/2,width:width,height:height),cornerRadius:12))
                layer.draw(Image(uiImage:image),in:CGRect(x:-width/2,y:-height/2,width:width,height:height))
            }
        }
    }
}

// A separate, persistent hosting boundary lets glass sample the scene without
// rebuilding the navigation/content hierarchy at the wallpaper's frame rate.
struct RanyBackdropHost: UIViewControllerRepresentable {
    @ObservedObject var ambience: RanyAmbience
    let reading: Bool
    let accountID: String?
    let assembly: Double
    var held = false
    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView:scene(context))
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        controller.view.accessibilityIdentifier = "rany.background.renderer"
        return controller
    }
    func updateUIViewController(_ controller: UIHostingController<AnyView>, context: Context) {
        withTransaction(context.transaction) { controller.rootView = scene(context) }
    }
    private func scene(_ context: Context) -> AnyView {
        AnyView(RanyBackdrop(ambience:ambience,reading:reading,accountID:accountID,assembly:assembly,held:held)
            .environment(\.self,context.environment))
    }
}
