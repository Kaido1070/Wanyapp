import Foundation

enum RanyProgressState: Equatable {
    case local, syncing, synchronized, saveFailed
    static func resolve(locallySaved: Bool, confirmed: Bool, pending: Bool, syncing: Bool, sessionValid: Bool) -> Self {
        guard locallySaved else { return .saveFailed }
        if syncing { return .syncing }
        return confirmed && !pending && sessionValid ? .synchronized : .local
    }
    var label: String {
        switch self {
        case .local: return "محفوظ على الجهاز"
        case .syncing: return "محفوظ على الجهاز · جارٍ المزامنة"
        case .synchronized: return "التقدم محفوظ ومتزامن"
        case .saveFailed: return "تعذر حفظ التقدم على الجهاز"
        }
    }
    var icon: String {
        switch self {
        case .local: return "internaldrive"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synchronized: return "checkmark.icloud"
        case .saveFailed: return "exclamationmark.triangle"
        }
    }
}
