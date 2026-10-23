import SwiftUI
import UIKit
import ImageIO

// One native scrolling/zooming surface for the whole chapter. UIKit owns its
// pinch transform and focal point; SwiftUI never resizes pages during a pinch.
struct ReaderChapterScroll: UIViewRepresentable {
    let id: String
    let endTitle: String
    let urls: [URL?]
    let ratios: [Int:CGFloat]
    let initialPage: Int
    let nextTitle: String?
    let online: Bool
    var quality: ImageQuality = .balanced
    var onNext: () -> Void
    var onBack: () -> Void
    var onRetry: () -> Void
    var onInvalid: (Int) -> Void
    var onPosition: (Int,Double,Bool) -> Void
    var onScroll: (CGFloat,Bool) -> Void
    func makeUIView(context: Context) -> ChapterScroll { let view = ChapterScroll(); updateUIView(view,context:context); return view }
    func updateUIView(_ view: ChapterScroll, context: Context) {
        view.onNext = onNext; view.onBack = onBack; view.onRetry = onRetry
        view.onInvalid = onInvalid; view.onPosition = onPosition; view.onScroll = onScroll
        view.configure(id:id,urls:urls,ratios:ratios,initialPage:initialPage,nextTitle:nextTitle,online:online,endTitle:endTitle,quality:quality)
    }
    static func dismantleUIView(_ view: ChapterScroll, coordinator: Void) { view.stop(); view.onPosition = nil; view.onScroll = nil; view.delegate = nil }
}

private struct DecodedChapterPage: @unchecked Sendable {
    let image: UIImage
    let ratio: CGFloat
    static func read(_ url: URL,quality: ImageQuality) -> Self? {
        guard !Task.isCancelled, let source = CGImageSourceCreateWithURL(url as CFURL,nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let w = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let h = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              w.doubleValue > 0, h.doubleValue > 0 else { return nil }
        let width = w.doubleValue, height = h.doubleValue
        let factor = quality.decodeFactor(width:width,height:height)
        let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceThumbnailMaxPixelSize:max(1,max(width,height)*factor),
            kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true]
        guard !Task.isCancelled, let cg = CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary), !Task.isCancelled else { return nil }
        return Self(image:UIImage(cgImage:cg),ratio:CGFloat(height/width))
    }
}

final class ChapterScroll: UIScrollView, UIScrollViewDelegate {
    let canvas = UIView()
    private(set) var tiles: [UIImageView] = []
    private var placeholders: [UILabel] = []
    private var retries: [UIButton] = []
    private let footer = UIStackView()
    private let endLabel = UILabel()
    private let nextButton = UIButton(type:.system)
    private let backButton = UIButton(type:.system)
    private var chapterID: String?
    private var urls: [URL?] = []
    private var ratios: [Int:CGFloat] = [:]
    private var pendingRatios: [Int:CGFloat] = [:]
    private var tasks: [Int:Task<Void,Never>] = [:]
    private var generation = UUID()
    private var quality: ImageQuality = .balanced
    private var restored = false
    private var initialPage = 0
    private var layoutWidth: CGFloat = 0
    private var applyingLayout = false
    private var interacted = false
    private var reportPending = false
    private var lastReport: TimeInterval = 0
    private(set) var geometryUpdates = 0
    var onNext: (() -> Void)?
    var onBack: (() -> Void)?
    var onRetry: (() -> Void)?
    var onInvalid: ((Int) -> Void)?
    var onPosition: ((Int,Double,Bool) -> Void)?
    var onScroll: ((CGFloat,Bool) -> Void)?
    private var zoomAnimationActive: Bool {
        if #available(iOS 17.4, *) { return isZoomAnimating }
        return false
    }
    private var busy: Bool { isTracking || isDragging || isDecelerating || isZooming || isZoomBouncing || zoomAnimationActive }
    override init(frame: CGRect) {
        super.init(frame:frame)
        backgroundColor = .black; canvas.backgroundColor = .black
        delegate = self; minimumZoomScale = 1; maximumZoomScale = 4
        bouncesZoom = true; alwaysBounceVertical = true
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        addSubview(canvas)
        footer.axis = .vertical; footer.spacing = 16; footer.alignment = .center
        endLabel.text = "نهاية الفصل"; endLabel.textColor = .white; endLabel.font = .preferredFont(forTextStyle:.headline)
        nextButton.addTarget(self,action:#selector(nextChapter),for:.touchUpInside)
        backButton.setTitle("العودة للفصول",for:.normal); backButton.addTarget(self,action:#selector(back),for:.touchUpInside)
        [nextButton,backButton].forEach { $0.tintColor = UIColor(red:0.87,green:0.71,blue:0.52,alpha:1); $0.heightAnchor.constraint(greaterThanOrEqualToConstant:44).isActive = true }
        [endLabel,nextButton,backButton].forEach { footer.addArrangedSubview($0) }
        canvas.addSubview(footer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func nextChapter() { onNext?() }
    @objc private func back() { onBack?() }
    @objc private func retry() { onRetry?() }
    func configure(id: String, urls: [URL?], ratios: [Int:CGFloat], initialPage: Int, nextTitle: String?, online: Bool, endTitle: String = "نهاية الفصل",quality: ImageQuality = .balanced) {
        if chapterID != id || tiles.count != urls.count {
            stop(); chapterID = id; self.initialPage = initialPage; restored = false; interacted = false
            self.ratios = ratios; pendingRatios = [:]; layoutWidth = 0
            setZoomScale(1,animated:false)
            tiles.forEach { $0.removeFromSuperview() }; placeholders.forEach { $0.removeFromSuperview() }; retries.forEach { $0.removeFromSuperview() }
            tiles = []; placeholders = []; retries = []
            for index in urls.indices {
                let image = UIImageView(); image.contentMode = .scaleAspectFit
                image.isAccessibilityElement = true; image.accessibilityLabel = "الصورة \(index+1)"
                canvas.addSubview(image); tiles.append(image)
                let label = UILabel(); label.text = "الصورة \(index+1) غير محملة"; label.textColor = .secondaryLabel
                label.textAlignment = .center; label.font = .preferredFont(forTextStyle:.subheadline)
                canvas.addSubview(label); placeholders.append(label)
                let button = UIButton(type:.system); button.setTitle("إعادة المحاولة",for:.normal)
                button.addTarget(self,action:#selector(retry),for:.touchUpInside); canvas.addSubview(button); retries.append(button)
            }
        }
        if self.quality != quality {
            stop(); self.quality=quality
            tiles.forEach { $0.image=nil }
        }
        for (index,url) in urls.enumerated() where self.urls.indices.contains(index) && self.urls[index] != url {
            tasks[index]?.cancel(); tasks[index] = nil; tiles[index].image = nil
        }
        self.urls = urls
        endLabel.text = endTitle
        nextButton.setTitle(nextTitle,for:.normal); nextButton.isHidden = nextTitle == nil
        for index in tiles.indices { retries[index].isEnabled = online; retries[index].isHidden = !online || tiles[index].image != nil }
        setNeedsLayout()
    }
    func stop() {
        generation = UUID(); tasks.values.forEach { $0.cancel() }; tasks.removeAll()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !applyingLayout, bounds.width > 0 else { return }
        if layoutWidth != bounds.width && !busy { rebuildGeometry() }
        refreshVisible()
    }
    private func visibleRect() -> CGRect { convert(bounds,to:canvas) }
    private func page(at y: CGFloat) -> Int { tiles.firstIndex(where: { $0.frame.maxY > y }) ?? max(0,tiles.count-1) }
    private func rebuildGeometry() {
        guard !applyingLayout, bounds.width > 0 else { return }
        applyingLayout = true
        let old = visibleRect(), oldPage = page(at:old.minY)
        let oldFrame = tiles.indices.contains(oldPage) ? tiles[oldPage].frame : .zero
        let fraction = oldFrame.height > 0 ? max(0,(old.minY-oldFrame.minY)/oldFrame.height) : 0
        let horizontal = layoutWidth > 0 ? old.minX/layoutWidth : 0
        let scale = zoomScale
        setZoomScale(1,animated:false)
        layoutWidth = bounds.width
        var y: CGFloat = 0
        for index in tiles.indices {
            let raw = ratios[index] ?? 1.6
            let ratio = raw.isFinite && raw > 0 ? raw : 1.6
            let height = layoutWidth * ratio
            tiles[index].frame = CGRect(x:0,y:y,width:layoutWidth,height:height)
            placeholders[index].frame = CGRect(x:0,y:y+max(0,height/2-24),width:layoutWidth,height:32)
            retries[index].frame = CGRect(x:0,y:y+height/2+12,width:layoutWidth,height:44)
            y += height
        }
        footer.frame = CGRect(x:12,y:y+28,width:max(1,layoutWidth-24),height:180)
        canvas.frame = CGRect(x:0,y:0,width:layoutWidth,height:y+236)
        contentSize = canvas.bounds.size
        setZoomScale(scale,animated:false)
        let selected = restored ? oldPage : min(max(0,initialPage),max(0,tiles.count-1))
        let rect = tiles.indices.contains(selected) ? tiles[selected].frame : .zero
        let target = CGPoint(x:horizontal*layoutWidth*scale,y:(rect.minY+(restored ? fraction*rect.height : 0))*scale)
        setContentOffset(CGPoint(x:min(max(0,target.x),max(0,contentSize.width-bounds.width)),y:min(max(0,target.y),max(0,contentSize.height-bounds.height))),animated:false)
        restored = true; geometryUpdates += 1; applyingLayout = false
    }
    private func settle() {
        if !busy && !pendingRatios.isEmpty {
            ratios.merge(pendingRatios,uniquingKeysWith: { _,new in new }); pendingRatios.removeAll(); rebuildGeometry()
        }
        refreshVisible(); report(force:true)
    }
    private func refreshVisible() {
        guard !applyingLayout, layoutWidth > 0 else { return }
        let visible = visibleRect()
        let nearby = visible.insetBy(dx:0,dy:-bounds.height/max(1,zoomScale))
        for index in tiles.indices {
            let wanted = tiles[index].frame.intersects(nearby)
            placeholders[index].isHidden = tiles[index].image != nil
            retries[index].isHidden = !retries[index].isEnabled || tiles[index].image != nil
            if !wanted {
                tiles[index].image = nil; tasks[index]?.cancel(); tasks[index] = nil
            } else if tiles[index].image == nil, tasks[index] == nil, urls.indices.contains(index), let url = urls[index] {
                let token = generation
                let quality=self.quality
                tasks[index] = Task { @MainActor [weak self] in
                    let decode = Task.detached(priority:.userInitiated) { DecodedChapterPage.read(url,quality:quality) }
                    let result = await withTaskCancellationHandler(operation: { await decode.value },onCancel: { decode.cancel() })
                    guard !Task.isCancelled, let self, self.generation == token, self.urls.indices.contains(index), self.urls[index] == url else { return }
                    self.tasks[index] = nil
                    if let result {
                        self.tiles[index].image = result.image; self.placeholders[index].isHidden = true; self.retries[index].isHidden = true
                        if abs((self.ratios[index] ?? 1.6)-result.ratio) > 0.0001 {
                            self.pendingRatios[index] = result.ratio
                            if !self.busy { self.settle() }
                        }
                    } else { self.onInvalid?(index) }
                }
            }
        }
    }
    private func report(force: Bool = false) {
        guard !applyingLayout, !isZooming, !isZoomBouncing, !zoomAnimationActive, !reportPending else { return }
        let now = Date.timeIntervalSinceReferenceDate
        guard force || now-lastReport > 0.08 else { return }
        lastReport = now; reportPending = true
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.reportPending = false
            guard self.generation == token, !self.isZooming, !self.isZoomBouncing, !self.zoomAnimationActive else { return }
            let rect = self.visibleRect()
            let percent = min(100,max(0,rect.minY/max(1,self.canvas.bounds.height-rect.height)*100))
            self.onPosition?(self.page(at:rect.minY),Double(percent),self.interacted)
            self.onScroll?(self.contentOffset.y,self.isDragging || self.isDecelerating)
        }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { interacted = true }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { refreshVisible() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        settle()
        DispatchQueue.main.async { [weak self] in self?.settle() }
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { interacted = true }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { refreshVisible(); report() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { settle() } }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle() }
}
