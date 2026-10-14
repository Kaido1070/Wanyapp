import CoreGraphics

struct ReaderLayout {
    var heights: [CGFloat]
    var total: CGFloat { heights.reduce(0,+) }
    func top(of page: Int) -> CGFloat { heights.prefix(max(0,min(page,heights.count))).reduce(0,+) }
    func page(at offset: CGFloat) -> Int {
        var end: CGFloat = 0
        for (index,height) in heights.enumerated() { end += height; if offset < end { return index } }
        return max(0,heights.count-1)
    }
    func preservingPosition(from old: ReaderLayout, offset: CGFloat) -> CGFloat {
        guard !old.heights.isEmpty, !heights.isEmpty else { return 0 }
        let page = min(old.page(at:offset),heights.count-1)
        let fraction = min(1,max(0,(offset-old.top(of:page))/max(1,old.heights[page])))
        return top(of:page)+heights[page]*fraction
    }
}
