import Foundation

struct ColumnFilter: Codable, Equatable {
    var includeKeywords: String?
    var excludeKeywords: String?
    var hideReplies: Bool
    var hideReposts: Bool

    init(
        includeKeywords: String? = nil,
        excludeKeywords: String? = nil,
        hideReplies: Bool = false,
        hideReposts: Bool = false
    ) {
        self.includeKeywords = includeKeywords?.trimmed.nonEmpty
        self.excludeKeywords = excludeKeywords?.trimmed.nonEmpty
        self.hideReplies = hideReplies
        self.hideReposts = hideReposts
    }

    var hasRules: Bool {
        includeKeywords != nil || excludeKeywords != nil || hideReplies || hideReposts
    }
}

extension ColumnFilter {
    static let none = ColumnFilter()
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        trimmed.isEmpty ? nil : trimmed
    }
}
