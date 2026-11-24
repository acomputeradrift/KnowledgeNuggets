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
        /// A `NuggetState` raw value. Missing in backups made before states existed.
        var state: String?
        /// Legacy: read from older backups, and still written so older app
        /// versions can read a new backup.
        var isActive: Bool?
        /// Position within its section. In older backups, only active ones were ordered.
        var sortOrder: Int
        var createdAt: Date
        var updatedAt: Date
        /// Legacy: when an inactive nugget was moved out on purpose. Read only
        /// from older backups, and missing in the oldest.
        var deactivatedAt: Date?

        init(
            id: UUID,
            text: String,
            author: String? = nil,
            book: String? = nil,
            category: String? = nil,
            kind: String? = nil,
            state: NuggetState?,
            sortOrder: Int = 0,
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.text = text
            self.author = author
            self.book = book
            self.category = category
            self.kind = kind
            self.state = state?.rawValue
            self.isActive = state.map { $0 == .active }
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deactivatedAt = nil
        }
    }

    /// 2 added `state`. Version 1 backups had only `isActive` and `deactivatedAt`.
    var version: Int = 2
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
            state: nugget.nuggetState,
            sortOrder: nugget.sortOrder,
            createdAt: nugget.createdAt,
            updatedAt: nugget.updatedAt
        )
    }
}

extension NuggetBackup.Item {
    var resolvedKind: NuggetKind {
        kind.map { NuggetKind(storedValue: $0) } ?? .default
    }

    /// The section it belongs in. Older backups map like the store migration:
    /// active stays active, inactive and never moved out on purpose is queued,
    /// moved out on purpose is paused.
    var resolvedState: NuggetState {
        if let state, let known = NuggetState(rawValue: state) { return known }
        if isActive ?? true { return .active }
        return deactivatedAt == nil ? .queued : .paused
    }

    /// False for an older backup's inactive nugget with no `deactivatedAt`: it
    /// may have been waiting for a spot, or moved out before that field existed.
    var isStateKnown: Bool {
        resolvedState != .queued || state != nil
    }

    /// Active first, then Queued, then Paused, each in its backup order, so
    /// each section keeps its shape and the rotation fills from the top.
    static func importOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        let left = lhs.resolvedState, right = rhs.resolvedState
        if left != right {
            return NuggetState.allCases.firstIndex(of: left)! < NuggetState.allCases.firstIndex(of: right)!
        }
        if lhs.state == nil, rhs.state == nil {
            // Older backups only ordered active nuggets.
            switch left {
            case .active: break
            case .queued:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            case .paused:
                let a = lhs.deactivatedAt ?? .distantPast, b = rhs.deactivatedAt ?? .distantPast
                if a != b { return a < b }
            }
        }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.createdAt < rhs.createdAt
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
