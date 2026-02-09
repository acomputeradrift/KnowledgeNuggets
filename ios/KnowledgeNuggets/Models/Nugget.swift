import Foundation

struct Nugget: Identifiable, Codable {
    let id: String
    var text: String
    var authorName: String?
    var bookTitle: String?
    var amazonLink: String?
    var category: String?
    var position: Int?
    var active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case authorName = "author_name"
        case bookTitle = "book_title"
        case amazonLink = "amazon_link"
        case category
        case position
        case active
    }
}
