import SwiftUI
import UIKit
import ImageIO

struct ZoomDecodedImage: @unchecked Sendable { let image: UIImage }
enum ReaderZoomImage {
    static func decode(_ url: URL) -> ZoomDecodedImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let w = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let h = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              w.doubleValue > 0, h.doubleValue > 0 else { return nil }
        let width = w.doubleValue, height = h.doubleValue
        let scale = min(1,min(3000/width,min(sqrt(24_000_000/(width*height)),24000/max(width,height))))
        let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:max(width,height)*scale,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else { return nil }
        return ZoomDecodedImage(image:UIImage(cgImage:image))
    }
}

struct ReaderImageZoomView: View {
    let url: URL
    let number: Int
    var onClose: () -> Void
    @State private var image: UIImage?
    @State private var failed = false
    @State private var reset = 0
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:16) {
                Button(action:onClose) { Label("إغلاق",systemImage:"xmark").frame(minHeight:44) }
                Spacer()
                Text("الصورة \(number)").font(.headline)
                Spacer()
                Button { reset += 1 } label: { Image(systemName:"arrow.counterclockwise").frame(width:44,height:44) }.accessibilityLabel("إعادة ضبط التقريب")
            }.padding(.horizontal,16).foregroundStyle(Theme.accent)
            if let image { ReaderZoomSurface(image:image,reset:reset) }
            else if failed { EmptyState(icon:"photo",title:"تعذر عرض الصورة",detail:"أغلق النافذة وأعد تحميل الصورة الناقصة من الفصل.").frame(maxHeight:.infinity) }
            else { ProgressView("تجهيز الصورة…").frame(maxWidth:.infinity,maxHeight:.infinity) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.black.ignoresSafeArea())
            .task(id:url) {
                let decoded = await Task.detached(priority:.userInitiated) { ReaderZoomImage.decode(url) }.value
                guard !Task.isCancelled else { return }
                image = decoded?.image; failed = decoded == nil
            }
            .accessibilityAction(.escape,onClose)
    }
}

struct ReaderZoomSurface: UIViewRepresentable {
    let image: UIImage
    var reset: Int = 0
    func makeUIView(context: Context) -> ZoomScroll { ZoomScroll() }
    func updateUIView(_ view: ZoomScroll, context: Context) { view.show(image,reset:reset) }
    static func dismantleUIView(_ view: ZoomScroll, coordinator: Void) { view.delegate = nil; view.photo.image = nil }
    final class ZoomScroll: UIScrollView, UIScrollViewDelegate {
        let photo = UIImageView()
        private var lastSize: CGSize = .zero
        private var resetID = -1
        private var needsFit = true
        private var widthScale: CGFloat = 1
        override init(frame: CGRect) {
            super.init(frame:frame)
            backgroundColor = .black; delegate = self
            contentInsetAdjustmentBehavior = .never; semanticContentAttribute = .forceLeftToRight
            bouncesZoom = true; showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
            photo.contentMode = .scaleAspectFit; addSubview(photo)
            let doubleTap = UITapGestureRecognizer(target:self,action:#selector(toggleZoom(_:))); doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)
            accessibilityLabel = "صورة قابلة للتقريب بإصبعين والتحريك"
        }
        required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
        func show(_ image: UIImage, reset: Int) {
            if photo.image !== image || resetID != reset {
                photo.image = image; resetID = reset; needsFit = true; setNeedsLayout()
            }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let image = photo.image, image.size.width > 0, bounds.width > 0, bounds.height > 0 else { return }
            if needsFit || lastSize != bounds.size {
                needsFit = false; lastSize = bounds.size
                minimumZoomScale = 1; maximumZoomScale = 1; setZoomScale(1,animated:false); photo.frame = CGRect(origin:.zero,size:image.size); contentSize = image.size
                widthScale = bounds.width/image.size.width
                maximumZoomScale = max(1,widthScale*6)
                minimumZoomScale = min(widthScale,bounds.height/image.size.height)
                setZoomScale(widthScale,animated:false)
                centerImage(); setContentOffset(CGPoint(x:-contentInset.left,y:-contentInset.top),animated:false)
            }
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
        private func centerImage() {
            let size = photo.bounds.size
            contentInset = UIEdgeInsets(top:max(0,(bounds.height-size.height*zoomScale)/2),left:max(0,(bounds.width-size.width*zoomScale)/2),bottom:max(0,(bounds.height-size.height*zoomScale)/2),right:max(0,(bounds.width-size.width*zoomScale)/2))
        }
        @objc private func toggleZoom(_ recognizer: UITapGestureRecognizer) {
            if zoomScale > widthScale*1.05 { setZoomScale(widthScale,animated:true); return }
            let target = min(maximumZoomScale,widthScale*2.5)
            let point = recognizer.location(in:photo)
            let size = CGSize(width:bounds.width/target,height:bounds.height/target)
            zoom(to:CGRect(x:point.x-size.width/2,y:point.y-size.height/2,width:size.width,height:size.height),animated:true)
        }
    }
}
