import Foundation

struct UserSettings: Codable {
    var sendTimeLocal: String
    var timezone: String
    var marketplace: String
    var sendPush: Bool
    var sendEmail: Bool

    enum CodingKeys: String, CodingKey {
        case sendTimeLocal = "send_time_local"
        case timezone
        case marketplace
        case sendPush = "send_push"
        case sendEmail = "send_email"
    }
}
