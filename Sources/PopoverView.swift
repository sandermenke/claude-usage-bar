import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: UsageModel
    @State private var showCookieInput = false
    @State private var showPreferences = false
    @State private var cookieText = ""

    // Persisted display preferences
    @AppStorage("showSession") private var showSession = true
    @AppStorage("showWeekly") private var showWeekly = true
    @AppStorage("showScopedWeekly") private var showScopedWeekly = true
    @AppStorage("showCredits") private var showCredits = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let err = model.error {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showPreferences {
                preferencesPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if model.hasFetched {
                VStack(alignment: .leading, spacing: 14) {
                    usageBars
                    if showCredits { creditsSection }
                }
            } else if !showPreferences {
                emptyState
            }

            if showCookieInput {
                cookieEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.18), value: showPreferences)
        .animation(.easeInOut(duration: 0.18), value: showCookieInput)
    }

    // MARK: – Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Claude Usage")
                .font(.headline)

            Spacer()

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 2)
            }

            IconButton(systemName: "arrow.clockwise", help: "Refresh") {
                model.fetch()
            }
            .disabled(!model.hasCookie)

            IconButton(systemName: "slider.horizontal.3", help: "Preferences", isActive: showPreferences) {
                showPreferences.toggle()
            }
        }
    }

    // MARK: – Preferences

    private var preferencesPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SHOW IN POPUP")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            prefToggle("Session (5 hour)", $showSession)
            prefToggle("Weekly (7 day)", $showWeekly)
            prefToggle(scopedWeeklyLabel, $showScopedWeekly)
                .disabled(model.scopedWeekly.isEmpty)
            prefToggle("Usage credits", $showCredits)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }

    /// Names the models the account actually has weekly limits for, so the
    /// toggle never advertises a row that can't appear.
    private var scopedWeeklyLabel: String {
        let names = model.scopedWeekly.map(\.model)
        return names.isEmpty ? "Weekly per-model (none)" : "Weekly \(names.joined(separator: ", "))"
    }

    private func prefToggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Text(label).font(.subheadline)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(.accentColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: – Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Set your session cookie to get started.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // MARK: – Usage bars

    @ViewBuilder
    private var usageBars: some View {
        if showSession {
            UsageRow(
                label: "Session (5 hour)",
                pct: model.session.utilization / 100,
                resetDate: model.session.resetsAt,
                showDate: false
            )
        }
        if showWeekly {
            UsageRow(
                label: "Weekly (7 day)",
                pct: model.weekly.utilization / 100,
                resetDate: model.weekly.resetsAt,
                showDate: true
            )
        }
        if showScopedWeekly {
            ForEach(model.scopedWeekly) { scoped in
                UsageRow(
                    label: "Weekly \(scoped.model)",
                    pct: scoped.bucket.utilization / 100,
                    resetDate: scoped.bucket.resetsAt,
                    showDate: true
                )
            }
        }
    }

    // MARK: – Usage credits

    @ViewBuilder
    private var creditsSection: some View {
        if let c = model.credits {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Usage credits").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(c.percent)% used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ProgressBar(pct: Double(c.percent) / 100, color: creditsColor(Double(c.percent) / 100))
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
        VStack(spacing: 10) {
            HStack {
                if let date = model.lastUpdated {
                    Label(
                        "Updated \(date.formatted(date: .omitted, time: .shortened))",
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                Link("by @sandermenke", destination: URL(string: "https://x.com/sandermenke")!)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                ChipButton(
                    title: model.hasCookie ? "Update Cookie" : "Set Cookie",
                    systemImage: "key.fill",
                    isActive: showCookieInput
                ) {
                    showCookieInput.toggle()
                }

                Spacer()

                ChipButton(title: "Quit", systemImage: "power", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    // MARK: – Cookie input

    private var cookieEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1. Go to claude.ai/settings/usage\n2. Open DevTools (⌘⌥I) → Network\n3. Refresh, click the \"usage\" request\n4. Copy the full Cookie header value")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $cookieText)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

// MARK: – Reusable controls

/// A square icon button with a native hover highlight (Control Center style).
struct IconButton: View {
    let systemName: String
    var help: String = ""
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundColor(isActive ? .accentColor : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(isActive ? 0.12 : (hovering ? 0.09 : 0)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A pill-shaped text/icon button with a subtle fill and hover highlight.
struct ChipButton: View {
    let title: String
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    private var tint: Color { role == .destructive ? .red : .primary }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let s = systemImage {
                    Image(systemName: s).font(.system(size: 10, weight: .semibold))
                }
                Text(title)
            }
            .font(.caption.weight(.medium))
            .foregroundColor(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(tint.opacity(isActive ? 0.16 : (hovering ? 0.12 : 0.07)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A rounded progress bar.
struct ProgressBar: View {
    let pct: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * min(pct, 1.0)))
            }
        }
        .frame(height: 6)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline.weight(.medium))
                Spacer()
                if let d = resetDate {
                    Text("Resets \(resetLabel(d))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            ProgressBar(pct: pct, color: color)
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
