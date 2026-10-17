import SwiftUI
import UIKit
import Combine

// Background artwork only. The existing RanyIntro owns every letter and the mark.
enum RanyOpeningMotion {
    static let duration = 4.3
    static func glide(_ value: Double) -> Double {
        let t = min(1,max(0,value))
        return t*t*t*(t*(t*6-15)+10)
    }
    static func camera(_ time: Double) -> Double { glide((time-1.08)/0.77) }
    static func distribution(_ time: Double) -> Double { glide((time-1.85)/1.25) }
    // Minimum-distance assignment from the temporary story wall to the original
    // fourteen slots. Image identities and final destinations never change.
    static let originCells = [0,1,2,3,4,8,5,6,7,11,9,12,10,13]
    static func origin(index: Int) -> CGPoint {
        let cell = originCells[index % originCells.count]
        return CGPoint(x:Double(cell%3)*139+55,y:Double(cell/3)*198+8)
    }
}

@MainActor final class RanyOpeningPalette: ObservableObject {
    struct Artwork: @unchecked Sendable {
        let original: [UIImage]
        let toned: [UIImage]
        let pages: [UIImage]
    }
    @Published private(set) var artwork: Artwork?

    func prepare(_ images: [UIImage]) async {
        guard artwork == nil else { return }
        let task = Task.detached(priority:.userInitiated) { Self.render(images) }
        let result = await withTaskCancellationHandler(operation:{ await task.value },onCancel:{ task.cancel() })
        guard !Task.isCancelled else { return }
        artwork = result
    }
    func release() { artwork = nil }

    nonisolated private static func render(_ images: [UIImage]) -> Artwork {
        let original = Array(images.prefix(14))
        let toned = original.map(tone)
        var pages: [UIImage] = []
        guard !toned.isEmpty else { return Artwork(original:original,toned:toned,pages:pages) }
        let layouts: [[CGRect]] = [
            [CGRect(x:0,y:0,width:390,height:320),CGRect(x:0,y:326,width:150,height:230),CGRect(x:156,y:326,width:234,height:230),CGRect(x:0,y:562,width:390,height:218)],
            [CGRect(x:0,y:0,width:390,height:230),CGRect(x:0,y:236,width:390,height:350),CGRect(x:0,y:592,width:194,height:188),CGRect(x:200,y:592,width:190,height:188)],
            [CGRect(x:0,y:0,width:184,height:360),CGRect(x:190,y:0,width:200,height:360),CGRect(x:0,y:366,width:390,height:414)]
        ]
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        // Fourteen offline sheets cover the short 9.2 fps montage; no per-frame filters.
        for n in 0..<14 {
            if Task.isCancelled { break }
            pages.append(UIGraphicsImageRenderer(size:CGSize(width:390,height:780),format:format).image { renderer in
                UIColor(red:143/255,green:132/255,blue:115/255,alpha:1).setFill()
                renderer.fill(CGRect(x:0,y:0,width:390,height:780))
                for (j,rect) in layouts[n%3].enumerated() {
                    let image = toned[(n*3+j)%toned.count]
                    renderer.cgContext.saveGState(); renderer.cgContext.clip(to:rect)
                    let scale = max(rect.width/image.size.width,rect.height/image.size.height)*1.13
                    let size = CGSize(width:image.size.width*scale,height:image.size.height*scale)
                    image.draw(in:CGRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height))
                    renderer.cgContext.restoreGState()
                }
            })
        }
        return Artwork(original:original,toned:toned,pages:pages)
    }

    nonisolated private static func tone(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let width = cg.width, height = cg.height, stride = width*4
        var bytes = [UInt8](repeating:0,count:stride*height)
        let converted: CGImage? = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:stride,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(cg,in:CGRect(x:0,y:0,width:CGFloat(width),height:CGFloat(height)))
            let pixels = buffer.bindMemory(to:UInt8.self)
            let shadow = [27.0,29.0,32.0], middle = [112.0,109.0,103.0], light = [223.0,193.0,149.0]
            for j in Swift.stride(from:0,to:pixels.count,by:4) {
                let original = [Double(pixels[j]),Double(pixels[j+1]),Double(pixels[j+2])]
                let luma = original[0]*0.2126+original[1]*0.7152+original[2]*0.0722
                let grain = Double((j*13)%31-15)*0.65
                let value = min(235,max(0,min(255,max(0,(luma-119)*1.6+113))*0.83+grain))/235
                let lower = value < 0.53, amount = lower ? value/0.53 : (value-0.53)/0.47
                let from = lower ? shadow : middle, to = lower ? middle : light
                for channel in 0..<3 {
                    let result = (from[channel]+(to[channel]-from[channel])*amount)*0.79+original[channel]*0.21
                    pixels[j+channel] = UInt8(min(255,max(0,result.rounded())))
                }
            }
            return context.makeImage()
        }
        return converted.map { UIImage(cgImage:$0,scale:image.scale,orientation:image.imageOrientation) } ?? image
    }
}

enum RanyGoldenOpening {
    private static func mix(_ a: CGFloat,_ b: CGFloat,_ t: CGFloat) -> CGFloat { a+(b-a)*t }

    static func draw(context: GraphicsContext,size: CGSize,time: Double,artwork: RanyOpeningPalette.Artwork,backdropTime: Double? = nil) {
        guard !artwork.original.isEmpty else { return }
        let pull = CGFloat(RanyOpeningMotion.camera(time)), distribution = CGFloat(RanyOpeningMotion.distribution(time))
        var scene = context
        let center = CGPoint(x:size.width/2,y:size.height*355/780)
        scene.translateBy(x:center.x,y:center.y)
        scene.rotate(by:.radians(Double(mix(-0.09,0,pull))))
        let zoom = mix(2.25,1,pull); scene.scaleBy(x:zoom,y:zoom)
        scene.translateBy(x:-center.x,y:-center.y)
        let width = min(min(size.width*0.30,size.height*0.15),190)
        let color = CGFloat(RanyOpeningMotion.glide((time-3.0)/1.3))
        for i in artwork.original.indices {
            let target = RanyBackdropMotion.position(index:i,elapsed:backdropTime ?? time,height:Double(size.height))
            let origin = RanyOpeningMotion.origin(index:i)
            let x = mix(origin.x/390*size.width,target.x*size.width,distribution)
            let y = mix(origin.y/780*size.height,target.y*size.height,distribution)
            let w = mix(size.width*138/390,width,distribution)
            let h = mix(size.height*196/780,width*248/180,distribution)
            var card = scene
            card.opacity = Double(mix(1,0.36,CGFloat(RanyOpeningMotion.glide((time-1.7)/0.95))))
            card.translateBy(x:x,y:y)
            card.rotate(by:.degrees(RanyBackdropMotion.angle(index:i)*Double(distribution)))
            let rect = CGRect(x:-w/2,y:-h/2,width:w,height:h)
            card.clip(to:Path(roundedRect:rect,cornerRadius:12*distribution))
            var ink = card; ink.opacity *= Double(1-color)
            ink.draw(Image(uiImage:artwork.toned[i]),in:rect)
            if color > 0 { var original = card; original.opacity *= Double(color); original.draw(Image(uiImage:artwork.original[i]),in:rect) }
        }
        if time < 1.32, !artwork.pages.isEmpty {
            var paper = context
            paper.opacity = 1-RanyOpeningMotion.glide((time-1.18)/0.14)
            pageTurn(context:paper,size:size,time:min(time,1.26),pages:artwork.pages)
        }
    }

    private static func pageTurn(context: GraphicsContext,size: CGSize,time: Double,pages: [UIImage]) {
        let q = time*9.2, n = Int(floor(q)), p = CGFloat(q-Double(n))
        func sheet(_ number: Int,_ context: GraphicsContext) {
            var layer = context
            layer.translateBy(x:size.width/2,y:size.height/2)
            layer.rotate(by:.radians(number%2 == 0 ? 0.055 : -0.055))
            // Slight overscan keeps the paper edges outside the display.
            layer.draw(Image(uiImage:pages[number%pages.count]),in:CGRect(x:-size.width*0.59-p*size.width*0.04,y:-size.height*0.58,width:size.width*1.18,height:size.height*1.16))
        }
        sheet(n+1,context)
        let edge = (450-p*540)/390*size.width, bend = sin(p*CGFloat.pi)*75/390*size.width
        var boundary = Path()
        boundary.move(to:CGPoint(x:-size.width,y:-40))
        boundary.addLine(to:CGPoint(x:edge-size.width/6,y:-40))
        boundary.addCurve(to:CGPoint(x:edge+size.width/6,y:size.height+40),control1:CGPoint(x:edge+bend,y:size.height*0.23),control2:CGPoint(x:edge-bend,y:size.height*0.73))
        boundary.addLine(to:CGPoint(x:-size.width,y:size.height+40)); boundary.closeSubpath()
        var leaf = context; leaf.clip(to:boundary); leaf.translateBy(x:-p*size.width*38/390,y:p*size.height*10/780)
        sheet(n,leaf)
        let colors: [Color] = [.clear,.black.opacity(0.4),Color(red:223/255,green:193/255,blue:149/255).opacity(0.16),.clear]
        context.fill(Path(CGRect(x:edge-40/390*size.width,y:0,width:78/390*size.width,height:size.height)),with:.linearGradient(Gradient(colors:colors),startPoint:CGPoint(x:edge-40/390*size.width,y:0),endPoint:CGPoint(x:edge+38/390*size.width,y:0)))
    }
}

// The selected preview starts with readable ink panels and gains depth as the
// camera pulls back. The normal app veil takes over only at the final handoff.
struct RanyOpeningShade: View {
    let time: Double
    var body: some View {
        Canvas { context,size in
            let bounds = Path(CGRect(origin:.zero,size:size))
            let amount = RanyOpeningMotion.glide((time-1.1)/1.5)
            let charcoal = Color(red:25/255,green:27/255,blue:29/255)
            let scale = size.width/390
            context.fill(bounds,with:.radialGradient(Gradient(colors:[charcoal.opacity(0.22+0.48*amount),charcoal.opacity(0.1)]),center:CGPoint(x:size.width/2,y:size.height*343/780),startRadius:40*scale,endRadius:480*scale))
            context.fill(bounds,with:.radialGradient(Gradient(colors:[Color(red:223/255,green:193/255,blue:149/255).opacity(0.075),.clear]),center:CGPoint(x:size.width*330/390,y:size.height*120/780),startRadius:0,endRadius:450*scale))
            context.fill(bounds,with:.radialGradient(Gradient(colors:[.clear,.black.opacity(0.56)]),center:CGPoint(x:size.width/2,y:size.height*350/780),startRadius:100*scale,endRadius:510*scale))
        }.allowsHitTesting(false)
    }
}
