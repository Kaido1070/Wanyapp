import Foundation
import CoreGraphics

enum RanyBackdropMotion {
    static func scatteredPosition(index: Int) -> CGPoint {
        let x = 0.08+Double((index*37+11)%101)/100*0.84
        let y = 0.04+Double((index*61+19)%103)/102*0.92
        return CGPoint(x:CGFloat(x),y:CGFloat(y))
    }
    static let pixelsPerSecond = 1.6
    // One closed circuit; each of the fourteen identities occupies exactly one slot.
    // Both column changes occur beyond the viewport, without duplicating a view.
    static func position(index: Int, elapsed: Double, height: Double) -> CGPoint {
        let duration = max(1,height)*3.6/pixelsPerSecond
        let phase = (max(0,elapsed)/duration+(Double(index)+0.5)/14).truncatingRemainder(dividingBy:1)
        if phase < 0.5 { return CGPoint(x:0.77,y:CGFloat(1.4-phase*3.6)) }
        return CGPoint(x:0.23,y:CGFloat(-0.4+(phase-0.5)*3.6))
    }
}
