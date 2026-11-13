import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The JSON backup format. Import also accepts a bare array of items.
struct NuggetBackup: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        var id: UUID
        var text: String
        var author: String?
        var book: String?
        var category: String?
        /// Missing in backups made before kinds existed; those were books.
        var kind: String?
        var isActive: Bool
        var sortOrder: Int
        var createdAt: Date
        var updatedAt: Date
        /// When it was moved out of the rotation on purpose. Missing in older backups.
        var deactivatedAt: Date?
    }

    var version: Int = 1
    var exportedAt: Date
    var nuggets: [Item]

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func encoded() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> NuggetBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = ISO8601DateFormatter().date(from: string) ?? withFraction.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(string)")
        }
        if let backup = try? decoder.decode(NuggetBackup.self, from: data) {
            return backup
        }
        let items = try decoder.decode([Item].self, from: data)
        return NuggetBackup(exportedAt: Date(), nuggets: items)
    }
}

extension NuggetBackup.Item {
    @MainActor
    init(_ nugget: Nugget) {
        self.init(
            id: nugget.id,
            text: nugget.text,
            author: nugget.author,
            book: nugget.book,
            category: nugget.category,
            kind: nugget.kind,
            isActive: nugget.isActive,
            sortOrder: nugget.sortOrder,
            createdAt: nugget.createdAt,
            updatedAt: nugget.updatedAt,
            deactivatedAt: nugget.deactivatedAt
        )
    }
}

extension NuggetBackup.Item {
    var resolvedKind: NuggetKind {
        kind.map { NuggetKind(storedValue: $0) } ?? .default
    }
}

/// A backup file that can be handed to the share sheet.
struct NuggetBackupFile: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.fileName)
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
