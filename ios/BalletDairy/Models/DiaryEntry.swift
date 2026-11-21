import Foundation
import SwiftData

/// One page of the diary — one practice day.
@Model
final class DiaryEntry {
    @Attribute(.unique) var id: UUID
    /// Start of the local day this page belongs to.
    var day: Date
    var text: String
    var classType: String
    var durationMinutes: Int
    /// 1–5 hearts: how the body felt.
    var energy: Int
    var movementIDs: [String]
    @Attribute(.externalStorage) var drawing: Data?
    var createdAt: Date
    var updatedAt: Date

    init(day: Date,
         text: String = "",
         classType: String = ClassType.class_.rawValue,
         durationMinutes: Int = 0,
         energy: Int = 0,
         movementIDs: [String] = [],
         drawing: Data? = nil,
         id: UUID = UUID(),
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: day)
        self.text = text
        self.classType = classType
        self.durationMinutes = durationMinutes
        self.energy = energy
        self.movementIDs = movementIDs
        self.drawing = drawing
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// A page counts as a practice once it has time or movements logged.
    var isPracticed: Bool { durationMinutes > 0 || !movementIDs.isEmpty }

    func touch() { updatedAt = .now }
}

enum ClassType: String, CaseIterable, Identifiable {
    case class_ = "Class", barre = "Barre", pointe = "Pointe", rehearsal = "Rehearsal", privateLesson = "Private", selfPractice = "Self-practice"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .class_: "figure.dance"
        case .barre: "figure.barre"
        case .pointe: "sparkle"
        case .rehearsal: "music.note"
        case .privateLesson: "person.2"
        case .selfPractice: "house"
        }
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}

extension Int {
    /// 90 -> "1h 30m"
    var minutesLabel: String {
        let h = self / 60, m = self % 60
        switch (h, m) {
        case (0, _): return "\(m)m"
        case (_, 0): return "\(h)h"
        default: return "\(h)h \(m)m"
        }
    }
}
