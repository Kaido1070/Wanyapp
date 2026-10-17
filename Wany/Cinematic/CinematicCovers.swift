import UIKit
import ImageIO

@MainActor enum CinematicCovers {
    static func cached(state: AccountState?,stories: [String:Story]) async -> [UIImage] {
        let owner=state?.user.id
        let interests=owner.flatMap { Disk.read([String].self,owner:$0,name:"cinema/interests.json") } ?? []
        let popular=Disk.read([Story].self,owner:"public-cinema",name:"popular.json") ?? []
        var catalog=Dictionary(popular.map { ($0.key,$0) },uniquingKeysWith:{ a,_ in a })
        catalog.merge(stories) { _,b in b }
        let keys=CinematicCoverPlan.keys(data:state?.data ?? AccountData(),stories:catalog,interests:interests,popular:popular.map(\.key))
        let urls=keys.map { key in
            owner.map { Disk.file($0,Disk.coverName(key)) } ?? Disk.file("public-cinema",Disk.coverName(key))
        }
        return await Task.detached(priority:.userInitiated) {
            var images: [UIImage] = [], signatures: [UInt64] = []
            for url in urls.prefix(24) {
                guard !Task.isCancelled, images.count < CinematicCoverPlan.limit else { break }
                if let source=CGImageSourceCreateWithURL(url as CFURL,nil),
                   let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:640,kCGImageSourceShouldCacheImmediately:true] as CFDictionary),
                   let hash=RanyCoverQuality.signature(cg), !signatures.contains(where:{ RanyCoverQuality.matches($0,hash) }) {
                    signatures.append(hash); images.append(UIImage(cgImage:cg))
                }
            }
            // Existing, reviewed bundled covers are the last offline fallback, not a fabricated ranking.
            for i in 1...14 where images.count < CinematicCoverPlan.limit {
                guard let original=UIImage(named:"RanyDefault\(i)"), let cg=original.cgImage,
                      let hash=RanyCoverQuality.signature(cg), !signatures.contains(where:{ RanyCoverQuality.matches($0,hash) }) else { continue }
                let factor=min(1,640/max(original.size.width,original.size.height))
                let size=CGSize(width:original.size.width*factor,height:original.size.height*factor)
                let format=UIGraphicsImageRendererFormat(); format.scale=1; format.opaque=true
                let image=UIGraphicsImageRenderer(size:size,format:format).image { _ in original.draw(in:CGRect(origin:.zero,size:size)) }
                signatures.append(hash); images.append(image)
            }
            return images
        }.value
    }
    /// Bounded preparation after the preview/intro. Never a prerequisite for opening the app.
    static func prefetch(store: AppStore) async {
        guard store.online else { return }
        let owner=store.state?.user.id, generation=API.shared.generation
        if let owner, let value=try? await API.shared.get("/api/personalization-state",as:JSONValue.self),store.state?.user.id == owner {
            let keys=(value["readingWorks"].array+value["followed"].array).map { $0["mangaId"].string }.filter { !$0.isEmpty }
            try? Disk.save(Array(Set(keys)).sorted(),owner:owner,name:"cinema/interests.json")
            for start in stride(from:0,to:min(40,keys.count),by:20) {
                guard generation == API.shared.generation, store.state?.user.id == owner else { return }
                if let response=try? await API.shared.get("/api/source/resolve",query:["keys":keys[start..<min(start+20,keys.count)].joined(separator:",")],as:ResolveResponse.self) {
                    for story in response.items { store.remember(story) }
                }
            }
        }
        var popular: [Story] = []
        for source in ["mangatime","teamx"] {
            guard generation == API.shared.generation,store.state?.user.id == owner else { return }
            if let result=try? await API.shared.get("/api/source/popular",query:["source":source,"page":"1"],as:APIList.self) { popular += result.items.prefix(8) }
        }
        guard generation == API.shared.generation,store.state?.user.id == owner else { return }
        if !popular.isEmpty { try? Disk.save(popular,owner:"public-cinema",name:"popular.json") }
        var catalog=Dictionary(popular.map { ($0.key,$0) },uniquingKeysWith:{ a,_ in a }); catalog.merge(store.stories) { _,b in b }
        let interests=owner.flatMap { Disk.read([String].self,owner:$0,name:"cinema/interests.json") } ?? []
        let keys=CinematicCoverPlan.keys(data:store.state?.data ?? AccountData(),stories:catalog,interests:interests,popular:popular.map(\.key))
        for key in keys.prefix(12) {
            guard generation == API.shared.generation,store.state?.user.id == owner,let story=catalog[key] else { return }
            // Only public popularity results may enter the shared guest cache.
            let folder=owner ?? "public-cinema", file=Disk.file(owner ?? "public-cinema",Disk.coverName(key))
            if FileManager.default.fileExists(atPath:file.path) { continue }
            if let request=try? API.shared.imageRequest(source:story.source,url:story.cover,referer:story.url,quality:.balanced),
               let (data,response)=try? await URLSession.shared.data(for:request), data.count < 8_000_000,
               (response as? HTTPURLResponse)?.statusCode == 200,
               generation == API.shared.generation,store.state?.user.id == owner,
               let source=CGImageSourceCreateWithData(data as CFData,nil),
               let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:640] as CFDictionary),
               let bytes=UIImage(cgImage:cg).jpegData(compressionQuality:0.86) {
                try? FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
                try? bytes.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
                if owner != nil { store.remember(story) }
                _ = folder
            }
        }
    }
}
