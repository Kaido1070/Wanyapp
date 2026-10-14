import CoreGraphics

// Read page visibility without feeding an anchor back into the scroll view.
enum ReaderPosition {
    static func visiblePage(frames: [Int:CGRect]) -> Int? {
        let visible = frames.filter { $0.value.maxY > 0 && $0.value.height > 0 }
        return visible.filter { $0.value.minY <= 0 }.max(by: { $0.value.minY < $1.value.minY })?.key
            ?? visible.min(by: { $0.value.minY < $1.value.minY })?.key
    }
}
