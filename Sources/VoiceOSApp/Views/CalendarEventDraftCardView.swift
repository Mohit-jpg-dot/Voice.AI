import SwiftUI
import AppKit
import VoiceOSCore

public struct CalendarEventDraftCardView: View {
    @ObservedObject var appState: AppState
    public let draft: CalendarEventDraft
    public var onSave: (CalendarEventDraft) -> Void
    public var onDismiss: () -> Void

    @State private var titleText: String = ""
    @State private var dateText: String = ""
    @State private var timeText: String = ""
    @State private var participantText: String = ""
    @State private var isSaving: Bool = false

    public init(
        appState: AppState,
        draft: CalendarEventDraft,
        onSave: @escaping (CalendarEventDraft) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.appState = appState
        self.draft = draft
        self.onSave = onSave
        self.onDismiss = onDismiss
        _titleText = State(initialValue: draft.title)
        _dateText = State(initialValue: draft.dateString)
        _timeText = State(initialValue: draft.timeString)
        _participantText = State(initialValue: draft.participants.first ?? "david@company.com")
    }

    private var displayTime: String {
        let d = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty && !t.isEmpty {
            return "\(d) · \(t)"
        } else if !d.isEmpty {
            return d
        } else if !t.isEmpty {
            return t
        }
        return "Thursday · 2:00 – 2:30 PM"
    }

    private var displayParticipant: String {
        let p = participantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty { return p }
        if let first = draft.participants.first, !first.isEmpty { return first }
        return "david@company.com"
    }

    private var headerIcon: some View {
        Group {
            if draft.isReminder || draft.type == .reminder {
                // Reminders Bullet Icon Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 22, height: 22)

                    Image(systemName: "list.bullet.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.15))
                }
            } else if draft.type == .googleMeet {
                // Google Meet / Calendar Video Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 22, height: 22)

                    // 4-color stylized Google Calendar / Meet badge
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(red: 0.26, green: 0.52, blue: 0.96))
                            .frame(height: 6)

                        Text("31")
                            .font(.system(size: 9.5, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.20, green: 0.22, blue: 0.26))
                            .padding(.top, 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            } else {
                // Official Calendar 31 Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 22, height: 22)

                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(red: 0.92, green: 0.26, blue: 0.21))
                            .frame(height: 6)

                        Text("31")
                            .font(.system(size: 9.5, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.20, green: 0.22, blue: 0.26))
                            .padding(.top, 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
    }

    private var platformIconName: String {
        if draft.isReminder || draft.type == .reminder {
            return "checklist"
        }
        if draft.type == .googleMeet || draft.platform.localizedCaseInsensitiveContains("meet") {
            return "video"
        }
        return "calendar"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Bar: App Icon Badge + "New Event" / "New Meeting" Title + Close Button
            HStack(spacing: 10) {
                headerIcon

                Text(draft.type.displayLabel)
                    .font(.system(size: 14.5, weight: .semibold, design: .default))
                    .foregroundColor(.white)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.40))
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Title Line
            TextField("Event Title", text: $titleText)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundColor(.white)

            // Accent Vibrant Blue Bar
            Capsule()
                .fill(Color(red: 0.23, green: 0.51, blue: 0.96))
                .frame(height: 2.5)

            // Time Row: Clock Icon + Date/Time String
            HStack(spacing: 9) {
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.65))
                    .frame(width: 16)

                Text(displayTime)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.92))

                Spacer()
            }

            // Participants Row: Person Icon + Recipient Capsule Chip
            HStack(spacing: 9) {
                Image(systemName: "person")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.65))
                    .frame(width: 16)

                HStack(spacing: 4) {
                    Text(displayParticipant)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.95))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4.5)
                .background(Color(red: 0.18, green: 0.22, blue: 0.28).opacity(0.95))
                .clipShape(Capsule())

                Spacer()
            }

            // Bottom Actions Bar: Platform Badge on Left, Blue Save Button on Right
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: platformIconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))

                    Text(draft.platform)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.85))
                }

                Spacer()

                Button(action: {
                    guard !isSaving else { return }
                    isSaving = true
                    var updated = draft
                    updated.title = titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? draft.title : titleText
                    updated.dateString = dateText
                    updated.timeString = timeText
                    if !participantText.isEmpty {
                        updated.participants = [participantText]
                    }
                    onSave(updated)
                }) {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.6)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text("Save")
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 7.5)
                    .background(Color(red: 0.08, green: 0.48, blue: 0.95))
                    .clipShape(Capsule())
                    .shadow(color: Color(red: 0.08, green: 0.48, blue: 0.95).opacity(0.40), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
        .padding(16)
        .background(Color(red: 0.13, green: 0.14, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .onAppear {
            if titleText.isEmpty { titleText = draft.title }
            if dateText.isEmpty { dateText = draft.dateString }
            if timeText.isEmpty { timeText = draft.timeString }
            if participantText.isEmpty, let first = draft.participants.first { participantText = first }
        }
    }
}

