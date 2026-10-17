import Foundation
import CoreGraphics

enum RanyBackdropMotion {
    static func scatteredPosition(index: Int) -> CGPoint {
        CGPoint(x:0.36+Double((index*37+11)%101)/100*0.28,
                y:0.34+Double((index*61+19)%103)/102*0.24)
    }
    // Fixed, unique slots: a quiet scattered library, never two circulating columns.
    private static let slots: [(Double,Double,Double)] = [
        (0.11,0.05,-10),(0.46,0.02,7),(0.85,0.12,-5),(0.02,0.31,8),
        (0.37,0.29,-6),(0.76,0.40,8),(1.02,0.32,-10),(0.12,0.57,-5),
        (0.52,0.61,9),(0.94,0.65,-7),(-0.02,0.87,8),(0.30,0.96,-9),
        (0.68,0.89,6),(1.04,0.99,-5)
    ]
    static func angle(index: Int) -> Double { slots[index % slots.count].2 }
    static func position(index: Int, elapsed: Double, height: Double) -> CGPoint {
        let slot = slots[index % slots.count]
        let phase = Double(index)*1.73
        let t = max(0,elapsed)/(11+Double(index%3)*2)*Double.pi
        // Drift is bounded to about ten points; identities never swap or wrap.
        return CGPoint(x:slot.0+sin(t+phase)*0.022,y:slot.1+cos(t*0.83+phase)*10/max(1,height))
    }
}
