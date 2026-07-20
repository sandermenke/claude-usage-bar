import Foundation
import UserNotifications

struct UsageBucket {
    var utilization: Double = 0      // 0–100
    var resetsAt: Date?
}

/// A weekly limit scoped to a single model, e.g. "Weekly Opus".
/// The API names the model at runtime, so the label isn't hardcoded.
struct ScopedBucket: Identifiable {
    var id: String { model }
    var model: String
    var bucket: UsageBucket
}

struct CreditsInfo {
    var enabled: Bool = false
    var usedMinor: Int = 0
    var limitMinor: Int = 0
    var percent: Int = 0
    var currency: String = "USD"
    var exponent: Int = 2
    var balanceMinor: Int?

    private func money(_ minor: Int) -> String {
        let value = Double(minor) / pow(10, Double(exponent))
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = currency
        fmt.maximumFractionDigits = exponent
        fmt.minimumFractionDigits = exponent
        return fmt.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    var usedText: String { money(usedMinor) }
    var limitText: String { money(limitMinor) }
    var balanceText: String? { balanceMinor.map { money($0) } }
}

@MainActor
final class UsageModel: ObservableObject {
    @Published var session = UsageBucket()       // 5-hour
    @Published var weekly = UsageBucket()        // 7-day
    @Published var scopedWeekly: [ScopedBucket] = []  // per-model 7-day limits
    @Published var credits: CreditsInfo?
    @Published var lastUpdated: Date?
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasFetched = false

    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 300  // 5 min

    // Notification thresholds
    private let thresholds = [25, 50, 75, 90]
    private var lastNotifiedThreshold = 0

    var cookie: String? {
        get { KeychainHelper.load() }
        set {
            if let v = newValue, !v.isEmpty {
                _ = KeychainHelper.save(cookie: v)
            } else {
                KeychainHelper.delete()
            }
        }
    }

    var hasCookie: Bool { !(cookie ?? "").isEmpty }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fetch() }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: – Fetch

    func fetch() {
        guard let cookie, !cookie.isEmpty else {
            error = "No session cookie set"
            return
        }
        isLoading = true
        error = nil

        Task {
            do {
                let orgId = try await resolveOrgId(cookie: cookie)
                let data = try await fetchUsage(orgId: orgId, cookie: cookie)
                parse(data)
                // Balance lives in a separate endpoint; treat it as supplementary.
                if let balance = try? await fetchBalance(orgId: orgId, cookie: cookie) {
                    credits?.balanceMinor = balance
                }
                lastUpdated = Date()
                hasFetched = true
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: – Networking

    private func resolveOrgId(cookie: String) async throws -> String {
        // Try extracting from cookie first
        let parts = cookie.components(separatedBy: ";")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("lastActiveOrg=") {
                return String(trimmed.dropFirst("lastActiveOrg=".count))
            }
        }
        // Fallback: bootstrap API
        var req = URLRequest(url: URL(string: "https://claude.ai/api/bootstrap")!)
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        applyHeaders(&req)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["account"] as? [String: Any],
              let orgId = account["lastActiveOrgId"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return orgId
    }

    private func fetchUsage(orgId: String, cookie: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://claude.ai/api/organizations/\(orgId)/usage")!)
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        applyHeaders(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw URLError(.init(rawValue: code))
        }
        return data
    }

    private func fetchBalance(orgId: String, cookie: String) async throws -> Int {
        var req = URLRequest(url: URL(string: "https://claude.ai/api/organizations/\(orgId)/prepaid/credits")!)
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        applyHeaders(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw URLError(.init(rawValue: code))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let amount = json["amount"] as? Int else {
            throw URLError(.cannotParseResponse)
        }
        return amount
    }

    private func applyHeaders(_ req: inout URLRequest) {
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        req.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
    }

    // MARK: – Parse

    private func parse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            error = "Invalid JSON"
            return
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func bucket(from key: String) -> UsageBucket? {
            guard let obj = json[key] as? [String: Any] else { return nil }
            var b = UsageBucket()
            if let u = obj["utilization"] as? Double { b.utilization = u }
            if let s = obj["resets_at"] as? String { b.resetsAt = fmt.date(from: s) }
            return b
        }

        if let s = bucket(from: "five_hour") { session = s }
        if let w = bucket(from: "seven_day") { weekly = w }
        scopedWeekly = parseScopedWeekly(json, fmt: fmt)

        if let spend = json["spend"] as? [String: Any] {
            var c = CreditsInfo()
            c.enabled = spend["enabled"] as? Bool ?? false
            if let used = spend["used"] as? [String: Any] {
                c.usedMinor = used["amount_minor"] as? Int ?? 0
                c.currency = used["currency"] as? String ?? c.currency
                c.exponent = used["exponent"] as? Int ?? c.exponent
            }
            if let limit = spend["limit"] as? [String: Any] {
                c.limitMinor = limit["amount_minor"] as? Int ?? 0
            }
            c.percent = spend["percent"] as? Int ?? 0
            credits = c
        } else {
            credits = nil
        }

        checkNotifications()
    }

    /// Per-model weekly limits live in `limits[]` as `weekly_scoped` entries.
    /// Older responses instead used top-level `seven_day_<model>` keys, which
    /// are still present but null on current accounts — so fall back to those.
    private func parseScopedWeekly(_ json: [String: Any], fmt: ISO8601DateFormatter) -> [ScopedBucket] {
        if let limits = json["limits"] as? [[String: Any]] {
            let scoped = limits.compactMap { entry -> ScopedBucket? in
                guard entry["kind"] as? String == "weekly_scoped",
                      let scope = entry["scope"] as? [String: Any],
                      let model = scope["model"] as? [String: Any],
                      let name = model["display_name"] as? String else { return nil }
                var b = UsageBucket()
                if let p = entry["percent"] as? Double { b.utilization = p }
                if let s = entry["resets_at"] as? String { b.resetsAt = fmt.date(from: s) }
                return ScopedBucket(model: name, bucket: b)
            }
            if !scoped.isEmpty { return scoped }
        }

        return ["seven_day_opus": "Opus", "seven_day_sonnet": "Sonnet"].compactMap { key, name in
            guard let obj = json[key] as? [String: Any] else { return nil }
            var b = UsageBucket()
            if let u = obj["utilization"] as? Double { b.utilization = u }
            if let s = obj["resets_at"] as? String { b.resetsAt = fmt.date(from: s) }
            return ScopedBucket(model: name, bucket: b)
        }
    }

    // MARK: – Notifications

    private func checkNotifications() {
        let pct = Int(session.utilization)
        for t in thresholds where pct >= t && lastNotifiedThreshold < t {
            sendNotification(percentage: pct, threshold: t)
            lastNotifiedThreshold = t
        }
        if pct < lastNotifiedThreshold {
            lastNotifiedThreshold = thresholds.filter { $0 <= pct }.last ?? 0
        }
    }

    private func sendNotification(percentage: Int, threshold: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Claude Usage Alert"
        content.body = "Session usage reached \(percentage)% (threshold: \(threshold)%)"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "usage-\(threshold)", content: content, trigger: nil)
        center.add(req)
    }

    func clearData() {
        cookie = nil
        session = UsageBucket()
        weekly = UsageBucket()
        scopedWeekly = []
        credits = nil
        hasFetched = false
        lastUpdated = nil
        error = nil
        lastNotifiedThreshold = 0
    }
}
