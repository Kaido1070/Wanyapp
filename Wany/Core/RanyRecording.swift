import Foundation

// Promotional screen recordings run a debug build against a demo account. Release
// builds never read these values.
enum RanyRecording {
    static let session: String? = {
        #if DEBUG
        let value = ProcessInfo.processInfo.environment["RANY_PROMO_SESSION"] ?? ""
        return value.isEmpty ? nil : value
        #else
        return nil
        #endif
    }()
    static let hidesSources: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["RANY_PROMO_HIDE_SOURCES"] == "1"
        #else
        return false
        #endif
    }()
}
