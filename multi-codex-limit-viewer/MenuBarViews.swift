//
//  MenuBarViews.swift
//  multi-codex-limit-viewer
//

import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        Group {
            if let activeAccount = viewModel.activeAccount,
               let activeWorkspace = viewModel.activeWorkspace {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(account: activeAccount, workspace: activeWorkspace)

                        Divider()

                        usageSection(account: activeAccount)

                        Divider()

                        accountsSection

                        Divider()

                        footerActions
                    }
                    .padding(20)
                }
                .frame(width: 360, height: 680)
            } else {
                emptyState
                    .frame(width: 360, height: 260)
            }
        }
        .background(.regularMaterial)
    }

    private func header(account: StoredAccount, workspace: StoredWorkspace) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex")
                    .font(.system(size: 24, weight: .semibold))

                if let updatedAt = viewModel.runtimeState(for: account.id).lastUpdatedAt {
                    Text("Updated \(updatedAt, style: .relative)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Waiting for first refresh")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.runtimeState(for: account.id).lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)

                    diagnosticsActions
                }

                if let transientError = viewModel.transientError,
                   transientError != viewModel.runtimeState(for: account.id).lastError {
                    Text(transientError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(3)

                    diagnosticsActions
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                Text(viewModel.displayedEmail(for: account))
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)

                WorkspacePicker(
                    account: account,
                    selectedWorkspace: workspace,
                    onSelect: { workspaceID in
                        viewModel.selectWorkspace(workspaceID, for: account.id)
                    }
                )

                Button {
                    Task {
                        await viewModel.refreshAll()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.05))
                )
            }
        }
    }

    private func usageSection(account: StoredAccount) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(viewModel.snapshot(for: account)?.meters ?? []) { meter in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(meter.title)
                            .font(.system(size: 22, weight: .semibold))

                        Spacer()

                        Text("\(Int(meter.usedPercent.rounded()))%")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    UsageBar(progress: meter.usedPercent / 100, height: 14)

                    if let resetsAt = meter.resetsAt {
                        Text("Resets in \(remainingText(until: resetsAt))")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Switch Account")
                .font(.system(size: 22, weight: .semibold))

            ForEach(viewModel.accounts) { account in
                AccountListRow(
                    account: account,
                    displayedEmail: viewModel.displayedEmail(for: account),
                    snapshot: viewModel.snapshot(for: account),
                    workspace: account.selectedWorkspace,
                    isActive: viewModel.activeAccount?.id == account.id
                ) {
                    viewModel.selectAccount(account.id)
                }
            }
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            FooterButton(icon: "plus", title: "Add Account") {
                Task {
                    await viewModel.addAccount()
                }
            }

            FooterButton(icon: "dot.radiowaves.left.and.right", title: "Status Page") {
                guard let url = URL(string: "https://status.openai.com") else {
                    return
                }
                NSWorkspace.shared.open(url)
            }

            FooterButton(icon: "doc.on.doc", title: "Copy Diagnostics") {
                viewModel.copyDiagnostics()
            }

            FooterButton(icon: "doc.text.magnifyingglass", title: "Open Log") {
                viewModel.revealDiagnosticsLog()
            }

            FooterButton(
                icon: viewModel.state.showEmails ? "eye.slash" : "eye",
                title: viewModel.state.showEmails ? "Hide Emails" : "Show Emails"
            ) {
                viewModel.toggleShowEmails()
            }

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            FooterButton(icon: "power", title: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Codex")
                .font(.system(size: 24, weight: .semibold))

            Text("No imported ChatGPT Codex account was found yet.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            if let error = viewModel.transientError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)

                diagnosticsActions
            }

            Button {
                Task {
                    await viewModel.addAccount()
                }
            } label: {
                Text("Add Account")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.codexTint)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Text("Add Account will first try the account currently logged into Codex, then open browser login if it is already in the list.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
    }

    private func remainingText(until date: Date) -> String {
        let remaining = max(0, date.timeIntervalSinceNow)
        let hours = Int(remaining) / 3_600
        let minutes = (Int(remaining) % 3_600) / 60
        let days = Int(remaining) / 86_400

        if days >= 2 {
            return "\(days)d"
        }

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(max(minutes, 1))m"
    }

    private var diagnosticsActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button("Copy Diagnostics") {
                    viewModel.copyDiagnostics()
                }

                Button("Open Log") {
                    viewModel.revealDiagnosticsLog()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))

            Text(viewModel.diagnosticsLogPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct StatusBarLabel: View {
    let snapshot: UsageSnapshot?
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.codexTint)

            VStack(spacing: 3) {
                TinyUsageBar(progress: progress(for: "primary"))
                TinyUsageBar(progress: progress(for: "secondary"))
            }

            if isRefreshing {
                Circle()
                    .fill(Color.codexTint)
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
    }

    private func progress(for meterID: String) -> Double {
        guard let snapshot else {
            return 0
        }
        return snapshot.meters.first(where: { $0.id == meterID })?.usedPercent ?? 0
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        Form {
            Section("Accounts") {
                Text("Imported accounts: \(viewModel.accounts.count)")
                Text("Stored at: \(viewModel.storagePath)")
                    .textSelection(.enabled)

                Button("Add Account") {
                    Task {
                        await viewModel.addAccount()
                    }
                }

                Button("Refresh Now") {
                    Task {
                        await viewModel.refreshAll()
                    }
                }
            }

            Section("Codex CLI") {
                Text(viewModel.codexExecutablePath ?? "codex executable not resolved yet")
                    .textSelection(.enabled)
            }

            Section("Diagnostics") {
                Text("Log file: \(viewModel.diagnosticsLogPath)")
                    .textSelection(.enabled)

                Button("Copy Diagnostics") {
                    viewModel.copyDiagnostics()
                }

                Button("Reveal Log In Finder") {
                    viewModel.revealDiagnosticsLog()
                }

                ScrollView {
                    Text(viewModel.diagnosticsReport.isEmpty ? "No diagnostics collected yet." : viewModel.diagnosticsReport)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 180)
            }

            Section("How To Add More Accounts") {
                Text("This app first snapshots the account currently logged into Codex.")
                Text("If that account is already imported, Add Account opens the Codex browser login flow and saves the new account into its own storage.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 520)
    }
}

private struct WorkspacePicker: View {
    let account: StoredAccount
    let selectedWorkspace: StoredWorkspace
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(account.workspaces) { workspace in
                Button {
                    onSelect(workspace.id)
                } label: {
                    HStack {
                        Text(workspace.menuLabel)
                        if workspace.id == selectedWorkspace.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(selectedWorkspace.menuLabel.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct AccountListRow: View {
    let account: StoredAccount
    let displayedEmail: String
    let snapshot: UsageSnapshot?
    let workspace: StoredWorkspace?
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayedEmail)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)

                        if let workspace {
                            Text(workspace.menuLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        if isActive {
                            badge(
                                title: "Current",
                                foreground: .white,
                                background: Color.codexTint
                            )
                        }

                        badge(
                            title: account.plan.title,
                            foreground: .secondary,
                            background: Color.black.opacity(0.05)
                        )
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    ForEach(displayMeters) { meter in
                        meterSummary(meter)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? Color.codexTint.opacity(0.12) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isActive ? Color.codexTint.opacity(0.45) : Color.black.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var displayMeters: [UsageMeter] {
        let meters = snapshot?.meters ?? []
        guard !meters.isEmpty else { return placeholderMeters }

        var selected: [UsageMeter] = []
        let preferredDurations = [300, 10_080]

        for duration in preferredDurations {
            if let meter = meters.first(where: { $0.windowDurationMinutes == duration }) {
                selected.append(meter)
            }
        }

        for meter in meters where !selected.contains(where: { $0.id == meter.id }) {
            selected.append(meter)
            if selected.count == 2 {
                break
            }
        }

        if selected.count < 2 {
            for placeholder in placeholderMeters where !selected.contains(where: { $0.windowDurationMinutes == placeholder.windowDurationMinutes }) {
                selected.append(placeholder)
                if selected.count == 2 {
                    break
                }
            }
        }

        return Array(selected.prefix(2))
    }

    private func meterSummary(_ meter: UsageMeter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summaryLabel(for: meter))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                UsageBar(progress: meter.usedPercent / 100, height: 8)
                    .frame(maxWidth: .infinity)

                Text("\(Int(meter.usedPercent.rounded()))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholderMeters: [UsageMeter] {
        [
            UsageMeter(id: "placeholder-5h", title: "5 Hours", usedPercent: 0, windowDurationMinutes: 300, resetsAt: nil),
            UsageMeter(id: "placeholder-1w", title: "Weekly", usedPercent: 0, windowDurationMinutes: 10_080, resetsAt: nil)
        ]
    }

    private func summaryLabel(for meter: UsageMeter) -> String {
        switch meter.windowDurationMinutes {
        case 300:
            return "5h"
        case 10_080:
            return "Weekly"
        case 1_440:
            return "Daily"
        case .some(let minutes) where minutes > 0:
            return meter.compactTitle
        default:
            return meter.title
        }
    }

    private func badge(title: String, foreground: Color, background: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
    }
}

private struct FooterButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct UsageBar: View {
    let progress: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.06))

                Capsule()
                    .fill(Color.codexTint)
                    .frame(width: max(8, geometry.size.width * max(0, min(progress, 1))))
            }
        }
        .frame(height: height)
    }
}

private struct TinyUsageBar: View {
    let progress: Double

    var body: some View {
        let clampedProgress = max(0, min(progress / 100, 1))

        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.black.opacity(0.10))
                .frame(width: 34, height: 4)

            Capsule()
                .fill(Color.codexTint)
                .frame(width: max(3, 34 * clampedProgress), height: 4)
        }
    }
}

private extension Color {
    static let codexTint = Color(red: 0.31, green: 0.71, blue: 0.80)
}
