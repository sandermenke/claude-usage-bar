import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: UsageModel
    @State private var showCookieInput = false
    @State private var cookieText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Claude Usage")
                    .font(.headline)
                Spacer()
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let err = model.error {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if model.hasFetched {
                usageBars
                creditsSection
                Divider()
                footer
            } else {
                Text("Set your session cookie below to get started.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }

            cookieSection

            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://x.com/sandermenke")!)
                }) {
                    Text("by @sandermenke")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 340)
    }

    // MARK: – Usage bars

    @ViewBuilder
    private var usageBars: some View {
        UsageRow(
            label: "Session (5 hour)",
            pct: model.session.utilization / 100,
            resetDate: model.session.resetsAt,
            showDate: false
        )
        UsageRow(
            label: "Weekly (7 day)",
            pct: model.weekly.utilization / 100,
            resetDate: model.weekly.resetsAt,
            showDate: true
        )
        if model.hasWeeklySonnet {
            UsageRow(
                label: "Weekly Sonnet",
                pct: model.weeklySonnet.utilization / 100,
                resetDate: model.weeklySonnet.resetsAt,
                showDate: true
            )
        }
    }

    // MARK: – Usage credits

    @ViewBuilder
    private var creditsSection: some View {
        if let c = model.credits {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Usage credits").font(.subheadline)
                    Spacer()
                    Text("\(c.percent)% used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(creditsColor(Double(c.percent) / 100))
                            .frame(width: geo.size.width * min(Double(c.percent) / 100, 1.0))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text("\(c.usedText) spent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(c.limitText) limit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let bal = c.balanceText {
                    Text("\(bal) balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func creditsColor(_ pct: Double) -> Color {
        if pct < 0.7 { return .accentColor }
        if pct < 0.9 { return .orange }
        return .red
    }

    // MARK: – Footer

    private var footer: some View {
        HStack {
            if let date = model.lastUpdated {
                Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Refresh") { model.fetch() }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    // MARK: – Cookie input

    @ViewBuilder
    private var cookieSection: some View {
        Button(showCookieInput ? "Hide Cookie" : (model.hasCookie ? "Update Cookie" : "Set Session Cookie")) {
            showCookieInput.toggle()
        }
        .buttonStyle(.borderless)
        .font(.caption)

        if showCookieInput {
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Go to claude.ai/settings/usage\n2. Open DevTools (⌘⌥I) → Network\n3. Refresh, click the \"usage\" request\n4. Copy the full Cookie header value")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $cookieText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3))
                    )

                HStack(spacing: 8) {
                    Button("Save & Fetch") {
                        guard !cookieText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            model.error = "Cookie is empty"
                            return
                        }
                        model.cookie = cookieText.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.fetch()
                        showCookieInput = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if model.hasCookie {
                        Button("Clear") {
                            cookieText = ""
                            model.clearData()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(6)
        }
    }
}

// MARK: – Usage Row

struct UsageRow: View {
    let label: String
    let pct: Double
    let resetDate: Date?
    let showDate: Bool

    private var color: Color {
        if pct < 0.7 { return .green }
        if pct < 0.9 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                if let d = resetDate {
                    Text("Resets \(resetLabel(d))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * min(pct, 1.0))
                }
            }
            .frame(height: 6)
            Text("\(Int(pct * 100))% used")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func resetLabel(_ date: Date) -> String {
        if showDate {
            return "on \(date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))"
        }
        return "at \(date.formatted(date: .omitted, time: .shortened))"
    }
}
