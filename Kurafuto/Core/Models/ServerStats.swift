import Foundation

/// Response of `GET /api/v2/servers/{id}/stats`.
/// Crafty returns some numbers as strings ("42.2MB", "5.0"), so decoding is lenient.
struct ServerStats: Codable, Hashable {
    var running: Bool
    var started: String?
    var cpu: Double
    var mem: String
    var memPercent: Double
    var worldName: String?
    var worldSize: String?
    var serverPort: Int?
    var online: Int
    var max: Int
    var players: [String]
    var desc: String?
    var icon: String?          // Base64 PNG of the server icon
    var version: String?
    var updating: Bool
    var waitingStart: Bool
    var firstRun: Bool
    var crashed: Bool

    enum CodingKeys: String, CodingKey {
        case running, started, cpu, mem
        case memPercent = "mem_percent"
        case worldName = "world_name"
        case worldSize = "world_size"
        case serverPort = "server_port"
        case online, max, players, desc, icon, version, updating
        case waitingStart = "waiting_start"
        case firstRun = "first_run"
        case crashed
    }

    init(running: Bool, started: String? = nil, cpu: Double, mem: String, memPercent: Double,
         worldName: String? = nil, worldSize: String? = nil, serverPort: Int? = nil,
         online: Int, max: Int, players: [String], desc: String? = nil, icon: String? = nil,
         version: String? = nil, updating: Bool = false, waitingStart: Bool = false,
         firstRun: Bool = false, crashed: Bool = false) {
        self.running = running; self.started = started; self.cpu = cpu; self.mem = mem
        self.memPercent = memPercent; self.worldName = worldName; self.worldSize = worldSize
        self.serverPort = serverPort; self.online = online; self.max = max; self.players = players
        self.desc = desc; self.icon = icon; self.version = version; self.updating = updating
        self.waitingStart = waitingStart; self.firstRun = firstRun; self.crashed = crashed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = try c.decodeIfPresent(Bool.self, forKey: .running) ?? false
        started = try? c.decodeIfPresent(String.self, forKey: .started)
        cpu = c.lenientDouble(.cpu)
        mem = (try? c.decodeIfPresent(String.self, forKey: .mem)) ?? "0MB"
        memPercent = c.lenientDouble(.memPercent)
        worldName = try? c.decodeIfPresent(String.self, forKey: .worldName)
        worldSize = try? c.decodeIfPresent(String.self, forKey: .worldSize)
        serverPort = try? c.decodeIfPresent(Int.self, forKey: .serverPort)
        online = (try? c.decodeIfPresent(Int.self, forKey: .online)) ?? 0
        max = (try? c.decodeIfPresent(Int.self, forKey: .max)) ?? 0
        // "players" arrives either as a JSON string ("[]") or as an array
        if let arr = try? c.decode([String].self, forKey: .players) {
            players = arr
        } else if let s = try? c.decode(String.self, forKey: .players),
                  let data = s.replacingOccurrences(of: "'", with: "\"").data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) {
            players = arr
        } else {
            players = []
        }
        desc = try? c.decodeIfPresent(String.self, forKey: .desc)
        icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        version = try? c.decodeIfPresent(String.self, forKey: .version)
        updating = (try? c.decodeIfPresent(Bool.self, forKey: .updating)) ?? false
        waitingStart = (try? c.decodeIfPresent(Bool.self, forKey: .waitingStart)) ?? false
        firstRun = (try? c.decodeIfPresent(Bool.self, forKey: .firstRun)) ?? false
        crashed = (try? c.decodeIfPresent(Bool.self, forKey: .crashed)) ?? false
    }

    var status: ServerStatus {
        if crashed { return .crashed }
        if updating { return .updating }
        if waitingStart { return .starting }
        return running ? .online : .offline
    }
}

enum ServerStatus: String {
    case online, offline, starting, updating, crashed

    var label: String {
        switch self {
        case .online: "Online"
        case .offline: "Offline"
        case .starting: "Starting…"
        case .updating: "Updating…"
        case .crashed: "Crashed"
        }
    }
}

/// Host values from `/metrics/host` (OpenMetrics text) or dashboard stats.
struct HostStats: Hashable {
    var cpuPercent: Double
    var memPercent: Double
    var diskUsage: [DiskUsage]
    var craftyVersion: String
}

struct DiskUsage: Hashable, Identifiable {
    var id: String { mount }
    var mount: String
    var usedGB: Double
    var totalGB: Double
}

extension KeyedDecodingContainer {
    func lenientDouble(_ key: Key) -> Double {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let s = try? decode(String.self, forKey: key) {
            let digits = s.filter { "0123456789.".contains($0) }
            return Double(digits) ?? 0
        }
        return 0
    }
}
