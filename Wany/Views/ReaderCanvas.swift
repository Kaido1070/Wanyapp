import SwiftUI
import UIKit
import ImageIO

// UIScrollView owns movement; SwiftUI never writes a page anchor back during a drag.
struct ReaderCanvas: UIViewRepresentable {
    let payload: ChapterPayload
    let files: [URL?]
    let restoredPage: Int
    let online: Bool
    let nextTitle: String?
    var onScroll: (Int, CGFloat, CGFloat, Bool) -> Void
    var onRetry: () -> Void
    var onInvalidImage: (Int) -> Void
    var onNext: () -> Void
    var onBack: () -> Void
    func makeUIView(context: Context) -> Canvas { Canvas() }
    func updateUIView(_ view: Canvas, context: Context) { view.configure(self) }
    static func dismantleUIView(_ view: Canvas, coordinator: Void) { view.shutdown() }

    final class Canvas: UIScrollView, UIScrollViewDelegate {
        private var input: ReaderCanvas?
        private var identity: String?
        private var displayedOnline: Bool?
        private var rows: [UIImageView] = []
        private var placeholders: [UIButton] = []
        private var layout = ReaderLayout(heights:[])
        private var ratios: [CGFloat] = []
        private var pendingRatios: [CGFloat]?
        private var width: CGFloat = 0
        private var restoring = false
        private var restorePage = 0
        private var initialized = false
        private var loading: Set<Int> = []
        private var lastFiles: [URL?] = []
        private var operations: [Int:Operation] = [:]
        private var tickets: [Int:UUID] = [:]
        private var loaded: [Int:URL] = [:]
        private var generation = UUID()
        private var lastNotify: CFTimeInterval = 0
        private let decoder = OperationQueue()
        private let footer = UIStackView()
        private let endLabel = UILabel()
        private let nextButton = UIButton(type:.system)
        private let backButton = UIButton(type:.system)
        override init(frame: CGRect) {
            super.init(frame:frame)
            delegate = self; backgroundColor = .black; alwaysBounceVertical = true
            contentInsetAdjustmentBehavior = .never
            decoder.maxConcurrentOperationCount = 2; decoder.qualityOfService = .userInitiated
            footer.axis = .vertical; footer.spacing = 16; footer.alignment = .center
            endLabel.textColor = .white; endLabel.font = .preferredFont(forTextStyle:.headline)
            endLabel.numberOfLines = 2; endLabel.textAlignment = .center
            nextButton.addTarget(self,action:#selector(nextChapter),for:.touchUpInside)
            backButton.setTitle("العودة للفصول",for:.normal)
            backButton.addTarget(self,action:#selector(back),for:.touchUpInside)
            for button in [nextButton,backButton] {
                button.tintColor = UIColor(red:0.87,green:0.73,blue:0.55,alpha:1)
                button.titleLabel?.font = .preferredFont(forTextStyle:.headline)
                button.heightAnchor.constraint(greaterThanOrEqualToConstant:44).isActive = true
            }
            footer.addArrangedSubview(endLabel); footer.addArrangedSubview(nextButton); footer.addArrangedSubview(backButton)
            addSubview(footer)
        }
        required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configure(_ value: ReaderCanvas) {
            input = value
            if identity != value.payload.id {
                generation = UUID(); decoder.cancelAllOperations(); loading = []; loaded = [:]; lastFiles = []; operations = [:]; tickets = [:]
                for row in rows { row.removeFromSuperview() }; for button in placeholders { button.removeFromSuperview() }
                identity = value.payload.id; displayedOnline = nil; initialized = false; restorePage = value.restoredPage
                ratios = value.payload.pages.indices.map { index in
                    if let metadata = value.payload.pageMeta, metadata.indices.contains(index),
                       let w = metadata[index].width, let h = metadata[index].height, w > 0, h > 0 { return CGFloat(h/w) }
                    return 1.6
                }
                rows = value.payload.pages.indices.map { _ in
                    let image = UIImageView(); image.contentMode = .scaleAspectFit; image.clipsToBounds = true; addSubview(image); return image
                }
                placeholders = value.payload.pages.indices.map { index in
                    let button = UIButton(type:.system); button.tag = index; button.tintColor = .lightGray
                    button.backgroundColor = UIColor(white:0.08,alpha:1); button.titleLabel?.numberOfLines = 2
                    button.titleLabel?.font = .preferredFont(forTextStyle:.caption1)
                    button.addTarget(self,action:#selector(retry),for:.touchUpInside); addSubview(button); return button
                }
            }
            endLabel.text = "نهاية الفصل \(chapterNumber(value.payload.number))"
            nextButton.setTitle(value.nextTitle,for:.normal); nextButton.isHidden = value.nextTitle == nil
            if displayedOnline != value.online {
            displayedOnline = value.online
            for (index,button) in placeholders.enumerated() {
                button.isEnabled = value.online
                button.setTitle(value.online ? "الصورة \(index+1) غير محملة\nاضغط لإعادة المحاولة" : "الصورة \(index+1) غير محملة · أوفلاين",for:.normal)
            }
            }
            if lastFiles != value.files {
                lastFiles = value.files
                var resolved = ratios
                for index in value.files.indices {
                    guard let url = value.files[index], let source = CGImageSourceCreateWithURL(url as CFURL,nil),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
                          let w = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                          let h = properties[kCGImagePropertyPixelHeight] as? NSNumber, w.doubleValue > 0 else { continue }
                    resolved[index] = CGFloat(h.doubleValue/w.doubleValue)
                    if loaded[index] != nil && loaded[index] != url { rows[index].image = nil; loaded[index] = nil }
                }
                if resolved != ratios {
                    if isTracking || isDragging || isDecelerating { pendingRatios = resolved }
                    else { applyRatios(resolved) }
                }
            }
            setNeedsLayout(); loadVisibleImages()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0 else { return }
            if width != bounds.width || !initialized {
                let old = layout; let offset = contentOffset.y
                width = bounds.width; layout = ReaderLayout(heights:ratios.map { width*$0 })
                arrange()
                restoring = true
                let target = initialized ? layout.preservingPosition(from:old,offset:offset) : layout.top(of:restorePage)
                initialized = true
                setContentOffset(CGPoint(x:0,y:min(max(0,target),max(0,contentSize.height-bounds.height))),animated:false)
                restoring = false
            }
            loadVisibleImages()
        }
        private func arrange() {
            var y: CGFloat = 0
            for index in rows.indices {
                let frame = CGRect(x:0,y:y,width:width,height:layout.heights[index])
                rows[index].frame = frame; placeholders[index].frame = frame; y += frame.height
            }
            footer.frame = CGRect(x:20,y:y+30,width:max(0,width-40),height:170)
            contentSize = CGSize(width:width,height:y+230)
        }
        private func applyRatios(_ value: [CGFloat]) {
            let old = layout; let offset = contentOffset.y
            ratios = value; pendingRatios = nil
            guard initialized else { return }
            layout = ReaderLayout(heights:ratios.map { width*$0 })
            restoring = true; arrange()
            setContentOffset(CGPoint(x:0,y:min(layout.preservingPosition(from:old,offset:offset),max(0,contentSize.height-bounds.height))),animated:false)
            restoring = false
        }
        private func loadVisibleImages() {
            guard initialized, let input else { return }
            let visible = CGRect(x:0,y:contentOffset.y-bounds.height*0.75,width:width,height:bounds.height*2.5)
            for index in rows.indices {
                guard rows[index].frame.intersects(visible) else {
                    rows[index].image = nil; loaded[index] = nil
                    operations[index]?.cancel(); operations[index] = nil; tickets[index] = nil; loading.remove(index)
                    continue
                }
                guard input.files.indices.contains(index), let url = input.files[index] else { continue }
                guard rows[index].image == nil, !loading.contains(index) else { continue }
                loading.insert(index)
                let token = generation
                let ticket = UUID(); tickets[index] = ticket
                let operation = BlockOperation { [weak self] in
                    let image = Self.decode(url)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == token, self.tickets[index] == ticket else { return }
                        self.loading.remove(index); self.operations[index] = nil; self.tickets[index] = nil
                        guard self.rows.indices.contains(index), self.input?.files[index] == url else { return }
                        let window = CGRect(x:0,y:self.contentOffset.y-self.bounds.height*0.75,width:self.width,height:self.bounds.height*2.5)
                        guard self.rows[index].frame.intersects(window) else { return }
                        if let image { self.rows[index].image = image; self.loaded[index] = url; self.placeholders[index].isHidden = true }
                        else { self.input?.onInvalidImage(index) }
                    }
                }
                operations[index] = operation; decoder.addOperation(operation)
            }
            for index in rows.indices { placeholders[index].isHidden = rows[index].image != nil }
        }
        nonisolated private static func decode(_ url: URL) -> UIImage? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any] else { return nil }
            let w = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 1000
            let h = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 1600
            let limit = min(16000,max(w,h)*min(1,1200/max(w,1)))
            let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:limit,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else { return nil }
            return UIImage(cgImage:image)
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { loadVisibleImages(); notify(force:false) }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { notify(force:true) }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView,willDecelerate decelerate: Bool) { if !decelerate { stopped() } }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { stopped() }
        private func stopped() { if let pendingRatios { applyRatios(pendingRatios) }; notify(force:true) }
        private func notify(force: Bool) {
            guard initialized, !restoring else { return }
            let now = CACurrentMediaTime(); guard force || now-lastNotify >= 0.1 else { return }; lastNotify = now
            let offset = max(0,contentOffset.y)
            let percent = min(100,max(0,offset/max(1,contentSize.height-bounds.height)*100))
            let page = layout.page(at:offset)
            let moving = isTracking || isDragging || isDecelerating
            let token = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.input?.onScroll(page,percent,offset,moving)
            }
        }
        func shutdown() { generation = UUID(); decoder.cancelAllOperations(); delegate = nil; input = nil; for row in rows { row.image = nil } }
        @objc private func retry() { input?.onRetry() }
        @objc private func nextChapter() { input?.onNext() }
        @objc private func back() { input?.onBack() }
    }
}
