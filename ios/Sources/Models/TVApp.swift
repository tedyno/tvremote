import Foundation

/// An app installed on the TV, as reported by `ed.installedApp.get`.
struct TVApp: Identifiable, Equatable, Hashable {
    let appId: String
    let name: String

    var id: String { appId }
}
