import Foundation
import CoreGraphics
import SwiftData

/// Fills the last few weeks with plausible practice so the calendar and charts can be previewed.
enum SampleData {
    static func fill(context: ModelContext, library: MovementLibrary, days: Int = 42) {
        var rng = SeededRandom(seed: 2026)
        let cal = Calendar.current
        let barre = library.movements(in: "barre").map(\.id)
        let centre = library.movements.filter { ["center", "turns", "petit_allegro", "grand_allegro", "linking"].contains($0.category) }.map(\.id)
        let notes = [
            "Pirouettes felt centred today — spotting earlier helped.",
            "Teacher said: lift out of the supporting hip in développé.",
            "Grand allegro combo: glissade, grand jeté, pas de bourrée, saut de chat.",
            "Ankles tired. Iced after class.",
            "Finally held the arabesque balance for a full count of four!",
            "Worked on épaulement in the adagio — think of the shoulders as a spiral.",
            "",
        ]
        let existing = Set((try? context.fetch(FetchDescriptor<DiaryEntry>()))?.map(\.day) ?? [])
        for back in 1...days {
            guard let day = cal.date(byAdding: .day, value: -back, to: .now)?.startOfDay, !existing.contains(day) else { continue }
            let weekday = cal.component(.weekday, from: day)
            if weekday == 1 || rng.unit() < 0.3 { continue } // Sundays & some rest days
            var moves: [String] = []
            for _ in 0..<Int(3 + rng.unit() * 4) { if let m = barre.randomElement(using: &rng) { moves.append(m) } }
            for _ in 0..<Int(2 + rng.unit() * 5) { if let m = centre.randomElement(using: &rng) { moves.append(m) } }
            let type: ClassType = rng.unit() < 0.15 ? .pointe : rng.unit() < 0.2 ? .selfPractice : .class_
            let e = DiaryEntry(day: day,
                               text: notes[Int(rng.unit() * CGFloat(notes.count - 1))],
                               classType: type.rawValue,
                               durationMinutes: [60, 75, 90, 90, 120][Int(rng.unit() * 4.99)],
                               energy: 2 + Int(rng.unit() * 3.99),
                               movementIDs: moves.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } })
            context.insert(e)
        }
        try? context.save()
    }
}

extension SeededRandom: RandomNumberGenerator {}
