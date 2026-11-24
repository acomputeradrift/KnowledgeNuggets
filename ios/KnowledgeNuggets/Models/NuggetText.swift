import Foundation

/// How a nugget's content is stored, shown and compared. Pure, so it's tested directly.
///
/// Content is stored without wrapping quotation marks and shown everywhere
/// wrapped in curly quotes, so every nugget looks the same whether or not it
/// was typed or pasted with quotes.
enum NuggetText {
    /// Quotation marks of any style that can wrap a nugget.
    static let quotationMarks: Set<Character> = ["\"", "“", "”", "„", "«", "»", "'", "‘", "’"]

    /// End punctuation ignored when looking for duplicates.
    static let endPunctuation: Set<Character> = [".", "!", "?", "…", ","]

    /// The content as it's stored: trimmed, with one layer of surrounding
    /// quotation marks removed. Quotes inside the text are left alone.
    static func stored(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let first = trimmed.first, let last = trimmed.last,
              quotationMarks.contains(first), quotationMarks.contains(last) else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The content as it's shown: wrapped in curly quotes. Strips one layer
    /// first, so text stored before the quote migration never shows doubled.
    static func quoted(_ text: String) -> String {
        "“\(stored(text))”"
    }

    /// What two nuggets are compared by: case-insensitive, whitespace collapsed
    /// and trimmed, quotation marks at the start and end removed, and trailing
    /// end punctuation ignored. Empty when there's nothing left to compare.
    static func matchKey(_ text: String) -> String {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        var characters = Substring(collapsed)
        while let first = characters.first, quotationMarks.contains(first) || first == " " {
            characters = characters.dropFirst()
        }
        while let last = characters.last,
              quotationMarks.contains(last) || endPunctuation.contains(last) || last == " " {
            characters = characters.dropLast()
        }
        return String(characters)
    }

    /// True when two pieces of content count as the same nugget.
    static func isDuplicate(_ lhs: String, _ rhs: String) -> Bool {
        let key = matchKey(lhs)
        return !key.isEmpty && key == matchKey(rhs)
    }
}
