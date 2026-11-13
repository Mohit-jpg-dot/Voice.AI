import Foundation

public enum EventDraftType: String, Codable, Sendable, CaseIterable {
    case calendar = "calendar"
    case googleMeet = "google_meet"
    case reminder = "reminder"

    public var displayLabel: String {
        switch self {
        case .calendar: return "New Event"
        case .googleMeet: return "New Meeting"
        case .reminder: return "New Reminder"
        }
    }

    public var defaultPlatform: String {
        switch self {
        case .calendar: return "Google Calendar"
        case .googleMeet: return "Google Meet"
        case .reminder: return "Reminders"
        }
    }
}

public struct CalendarEventDraft: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var type: EventDraftType
    public var dateString: String
    public var timeString: String
    public var participants: [String]
    public var platform: String
    public var notes: String?
    public var isReminder: Bool
    public var startsInMinutes: Int
    public var durationMinutes: Int
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        type: EventDraftType = .googleMeet,
        dateString: String = "Thursday",
        timeString: String = "2:00 – 2:30 PM",
        participants: [String] = [],
        platform: String = "Google Meet",
        notes: String? = nil,
        isReminder: Bool = false,
        startsInMinutes: Int = 60,
        durationMinutes: Int = 30,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.dateString = dateString
        self.timeString = timeString
        self.participants = participants
        self.platform = platform
        self.notes = notes
        self.isReminder = isReminder
        self.startsInMinutes = startsInMinutes
        self.durationMinutes = durationMinutes
        self.createdAt = createdAt
    }
}

