import Foundation
import SwiftData

/// Wire format shared with the FastAPI backend (backend/app/schemas.py).
struct EntryDTO: Codable, Equatable {
    var id: UUID
    var day: String               // yyyy-MM-dd (local day)
    var text: String
    var classType: String
    var durationMinutes: Int
    var energy: Int
    var movementIds: [String]
    var drawing: String?          // base64 PencilKit data
    var updatedAt: Date
    var deleted: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, day, text, energy, drawing, deleted
        case classType = "class_type", durationMinutes = "duration_minutes"
        case movementIds = "movement_ids", updatedAt = "updated_at"
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(_ e: DiaryEntry) {
        id = e.id
        day = Self.dayFormatter.string(from: e.day)
        text = e.text
        classType = e.classType
        durationMinutes = e.durationMinutes
        energy = e.energy
        movementIds = e.movementIDs
        drawing = e.drawing?.base64EncodedString()
        updatedAt = e.updatedAt
    }

    func apply(to e: DiaryEntry) {
        e.day = Self.dayFormatter.date(from: day).map { Calendar.current.startOfDay(for: $0) } ?? e.day
        e.text = text
        e.classType = classType
        e.durationMinutes = durationMinutes
        e.energy = energy
        e.movementIDs = movementIds
        e.drawing = drawing.flatMap { Data(base64Encoded: $0) }
        e.updatedAt = updatedAt
    }
}

struct SyncRequest: Codable {
    var since: Date?
    var entries: [EntryDTO]
}

struct SyncResponse: Codable {
    var serverTime: Date
    var entries: [EntryDTO]
    enum CodingKeys: String, CodingKey { case serverTime = "server_time", entries }
}

enum APIError: LocalizedError {
    case badURL, http(Int), transport(String)
    var errorDescription: String? {
        switch self {
        case .badURL: "The server address doesn't look right."
        case .http(let code): "The server answered with an error (\(code))."
        case .transport(let msg): msg
        }
    }
}

struct APIClient {
    var baseURL: URL
    var deviceID: String

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var c = enc.singleValueContainer()
            try c.encode(f.string(from: date))
        }
        return e
    }
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            if let d = f1.date(from: s) ?? f2.date(from: s) { return d }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }

    func health() async throws -> Bool {
        let (_, resp) = try await URLSession.shared.data(from: baseURL.appending(path: "health"))
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    func sync(_ req: SyncRequest) async throws -> SyncResponse {
        var r = URLRequest(url: baseURL.appending(path: "sync"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        r.httpBody = try encoder.encode(req)
        r.timeoutInterval = 20
        do {
            let (data, resp) = try await URLSession.shared.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw APIError.http(code) }
            return try decoder.decode(SyncResponse.self, from: data)
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }
}

/// Two-way, last-writer-wins sync of diary pages.
@MainActor
enum SyncService {
    static let serverKey = "serverURL"
    static let lastSyncKey = "lastSync"

    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "deviceID")
        return id
    }

    /// Returns a short human summary, e.g. "Sent 3 · received 1".
    static func sync(context: ModelContext) async throws -> String {
        let raw = UserDefaults.standard.string(forKey: serverKey) ?? "http://127.0.0.1:8000"
        guard let url = URL(string: raw) else { throw APIError.badURL }
        let client = APIClient(baseURL: url, deviceID: deviceID)
        let last = UserDefaults.standard.object(forKey: lastSyncKey) as? Date

        let all = try context.fetch(FetchDescriptor<DiaryEntry>())
        let outgoing = all
            .filter { last == nil || $0.updatedAt > last! }
            .filter { $0.isPracticed || !$0.text.isEmpty || $0.drawing != nil }
            .map { EntryDTO($0) }

        let resp = try await client.sync(SyncRequest(since: last, entries: outgoing))
        var received = 0
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for dto in resp.entries {
            if let local = byID[dto.id] {
                if dto.deleted { context.delete(local); received += 1 }
                else if dto.updatedAt > local.updatedAt { dto.apply(to: local); received += 1 }
            } else if !dto.deleted {
                let e = DiaryEntry(day: .now, id: dto.id)
                dto.apply(to: e)
                context.insert(e)
                received += 1
            }
        }
        try context.save()
        UserDefaults.standard.set(resp.serverTime, forKey: lastSyncKey)
        return "Sent \(outgoing.count) · received \(received)"
    }
}
