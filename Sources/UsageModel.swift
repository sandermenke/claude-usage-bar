import Foundation
import UserNotifications

struct UsageBucket {
    var utilization: Double = 0      // 0–100
    var resetsAt: Date?
}

@MainActor
final class UsageModel: ObservableObject {
    @Published var session = UsageBucket()       // 5-hour
    @Published var weekly = UsageBucket()        // 7-day
    @Published var weeklySonnet = UsageBucket()  // 7-day sonnet (Pro)
    @Published var hasWeeklySonnet = false
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
        if let ws = bucket(from: "seven_day_sonnet") {
            weeklySonnet = ws
            hasWeeklySonnet = true
        } else {
            hasWeeklySonnet = false
        }

        checkNotifications()
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
        weeklySonnet = UsageBucket()
        hasWeeklySonnet = false
        hasFetched = false
        lastUpdated = nil
        error = nil
        lastNotifiedThreshold = 0
    }
}
