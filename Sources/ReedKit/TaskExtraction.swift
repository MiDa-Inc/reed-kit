import Foundation

/// Structured task extracted from a dictation transcript by the
/// [[TaskExtractor]] client. Mirrors reed-backend's `TaskExtraction`
/// response model exactly — any change here must be made on both sides,
/// since the backend is the source of truth for the schema.
///
/// Every field except `title` is optional. The backend signals "the
/// transcript wasn't task-shaped" by returning the whole task as nil
/// (not a TaskExtraction with `title == nil`), so once you have a
/// `TaskExtraction` the title is always populated. Other fields are
/// nil when the user didn't address them — never invented to fill the
/// slot.
public struct TaskExtraction: Codable, Equatable, Sendable {
    public var title: String?
    public var description: String?
    /// ISO-8601 date (YYYY-MM-DD). String rather than `Date` so partial
    /// or model-resolved values round-trip without timezone surprises.
    public var dueDate: String?
    public var priority: Priority?
    public var assignees: [String]?
    public var subtasks: [String]?
    public var tags: [String]?

    public enum Priority: String, Codable, Equatable, Sendable, CaseIterable {
        case low
        case medium
        case high
    }

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case dueDate = "due_date"
        case priority
        case assignees
        case subtasks
        case tags
    }

    public init(
        title: String? = nil,
        description: String? = nil,
        dueDate: String? = nil,
        priority: Priority? = nil,
        assignees: [String]? = nil,
        subtasks: [String]? = nil,
        tags: [String]? = nil
    ) {
        self.title = title
        self.description = description
        self.dueDate = dueDate
        self.priority = priority
        self.assignees = assignees
        self.subtasks = subtasks
        self.tags = tags
    }
}
