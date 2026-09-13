import Foundation

struct CodexBridgeRequest: Codable {
    let id: String
    let method: String
    let params: [String: String]?
}

struct CodexBridgeReply: Codable {
    let id: String
    let ok: Bool
    let error: String?
}

enum CodexBridgeMethod: String {
    case status
    case login
    case logout
    case models
    case chat
}
