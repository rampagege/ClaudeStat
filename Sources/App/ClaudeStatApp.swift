import SwiftUI
import Domain
import Infrastructure
import Combine
#if ENABLE_SPARKLE
import Sparkle
#endif

/// Manages background sync outside of SwiftUI view hierarchy to avoid layout loops
@MainActor
final class BackgroundSyncManager {
    private var monitor: QuotaMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var syncTask: Task<Void, Never>?
    private var lastInterval: Double = 0
    private var lastEnabled: Bool = false

    func configure(monitor: QuotaMonitor) {
        self.monitor = monitor

        // Check settings periodically (every 1 second) to detect changes
        // This avoids SwiftUI onChange which can cause layout loops
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkAndUpdateSync()
            }
            .store(in: &cancellables)

        // Initial check
        checkAndUpdateSync()
    }

    private func checkAndUpdateSync() {
        let settings = AppSettings.shared
        let enabled = settings.backgroundSyncEnabled
        let interval = settings.backgroundSyncInterval

        // Only act if something changed
        if enabled != lastEnabled || (enabled && interval != lastInterval) {
            lastEnabled = enabled
            lastInterval = interval

            if enabled {
                startSync(interval: interval)
            } else {
                stopSync()
            }
        }
    }

    private func startSync(interval: Double) {
        guard let monitor = monitor else { return }

        // Cancel existing task
        syncTask?.cancel()
        monitor.stopMonitoring()

        AppLog.monitor.info("BackgroundSyncManager: Starting sync (interval: \(interval)s)")

        syncTask = Task {
            let stream = monitor.startMonitoring(interval: .seconds(interval))
            for await _ in stream {
                // Events handled internally by QuotaMonitor
            }
        }
    }

    private func stopSync() {
        AppLog.monitor.info("BackgroundSyncManager: Stopping sync")
        syncTask?.cancel()
        syncTask = nil
        monitor?.stopMonitoring()
    }
}

@main
struct ClaudeStatApp: App {
    /// The main domain service - monitors all AI providers
    /// This is the single source of truth for providers and their state
    @State private var monitor: QuotaMonitor

    /// Alerts users when quota status degrades
    private let quotaAlerter = NotificationAlerter()

    /// Manages background sync outside SwiftUI to avoid layout loops
    private let backgroundSyncManager = BackgroundSyncManager()

    #if ENABLE_SPARKLE
    /// Sparkle updater for auto-updates
    @State private var sparkleUpdater = SparkleUpdater()
    #endif

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        AppLog.ui.info("ClaudeStat v\(version) (\(build)) initializing...")

        // Create the shared repository
        // UserDefaultsProviderSettingsRepository implements all sub-protocols:
        // - ProviderSettingsRepository (base)
        // - ZaiSettingsRepository (Z.ai specific config)
        // - CopilotSettingsRepository (Copilot specific config + credentials)
        // - BedrockSettingsRepository (AWS Bedrock config)
        let settingsRepository = UserDefaultsProviderSettingsRepository.shared

        // Create all providers with their probes (rich domain models)
        // Each provider manages its own isEnabled state (persisted via ProviderSettingsRepository)
        // Each probe checks isAvailable() for credentials/prerequisites
        let repository = AIProviders(providers: [
            ClaudeProvider(probe: ClaudeUsageProbe(), passProbe: ClaudePassProbe(), settingsRepository: settingsRepository),
            CodexProvider(probe: CodexUsageProbe(), settingsRepository: settingsRepository),
            GeminiProvider(probe: GeminiUsageProbe(), settingsRepository: settingsRepository),
            AntigravityProvider(probe: AntigravityUsageProbe(), settingsRepository: settingsRepository),
            ZaiProvider(
                probe: ZaiUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            CopilotProvider(
                probe: CopilotUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            BedrockProvider(
                probe: BedrockUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
        ])
        AppLog.providers.info("Created \(repository.all.count) providers")

        // Initialize the domain service with quota alerter
        // QuotaMonitor automatically validates selected provider on init
        monitor = QuotaMonitor(
            providers: repository,
            alerter: quotaAlerter
        )
        AppLog.monitor.info("QuotaMonitor initialized")

        // Configure background sync manager
        backgroundSyncManager.configure(monitor: monitor)

        // Note: Notification permission is requested in onAppear, not here
        // Menu bar apps need the run loop to be active before requesting permissions

        AppLog.ui.info("ClaudeStat initialization complete")
    }

    /// App settings for theme
    @State private var settings = AppSettings.shared

    /// Cached quota values for status bar (to avoid @Observable triggering MenuBarExtra redraws)
    @State private var statusBarSession: Double?
    @State private var statusBarWeek: Double?

    /// Whether initial fetch has been done
    @State private var hasInitialFetch = false

    /// Current theme mode from settings
    private var currentThemeMode: ThemeMode {
        ThemeMode(rawValue: settings.themeMode) ?? .system
    }

    var body: some Scene {
        MenuBarExtra {
            #if ENABLE_SPARKLE
            MenuContentView(monitor: monitor, quotaAlerter: quotaAlerter)
                .appThemeProvider(themeModeId: settings.themeMode)
                .environment(\.sparkleUpdater, sparkleUpdater)
                .onAppear { updateStatusBarCache() }
            #else
            MenuContentView(monitor: monitor, quotaAlerter: quotaAlerter)
                .appThemeProvider(themeModeId: settings.themeMode)
                .onAppear { updateStatusBarCache() }
            #endif
        } label: {
            // Show Session and Week quotas as vertical bars (like iStat Menus)
            // Uses cached values to avoid @Observable triggering redraws
            StatusBarLabel(
                sessionPercent: statusBarSession,
                weekPercent: statusBarWeek
            )
            .task {
                guard !hasInitialFetch else { return }
                hasInitialFetch = true
                // Fetch Claude (default provider) quota on app launch
                await monitor.refresh(providerId: "claude")
                updateStatusBarCache()
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// Updates the cached status bar values from monitor
    private func updateStatusBarCache() {
        statusBarSession = monitor.selectedProvider?.snapshot?.sessionQuota?.percentRemaining
        statusBarWeek = monitor.selectedProvider?.snapshot?.weeklyQuota?.percentRemaining
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value = value else { return "--" }
        return "\(Int(value))%"
    }
}

/// Menu bar label that renders quota bars as an Image (like iStat Menus).
/// Label on LEFT, vertical bar on RIGHT, filling from bottom to top.
/// Caches last known values to UserDefaults for persistence across launches.
struct StatusBarLabel: View {
    let sessionPercent: Double?
    let weekPercent: Double?

    // Cache keys
    private static let sessionCacheKey = "com.claudestat.cache.sessionPercent"
    private static let weekCacheKey = "com.claudestat.cache.weekPercent"

    // Get effective values (use cached if current is nil)
    private var effectiveSession: Double {
        if let session = sessionPercent {
            // Save to cache when we have real data
            UserDefaults.standard.set(session, forKey: Self.sessionCacheKey)
            return session
        }
        return UserDefaults.standard.double(forKey: Self.sessionCacheKey)
    }

    private var effectiveWeek: Double {
        if let week = weekPercent {
            // Save to cache when we have real data
            UserDefaults.standard.set(week, forKey: Self.weekCacheKey)
            return week
        }
        return UserDefaults.standard.double(forKey: Self.weekCacheKey)
    }

    var body: some View {
        Image(nsImage: renderStatusBarImage())
    }

    private func renderStatusBarImage() -> NSImage {
        // Dimensions matching iStat Menus style
        let barWidth: CGFloat = 8       // Narrower like iStat
        let barHeight: CGFloat = 16     // Taller like iStat
        let labelWidth: CGFloat = 11    // Label + more spacing from bar
        let groupSpacing: CGFloat = 4   // Space between S group and W group

        // Each group: label + bar
        let groupWidth: CGFloat = labelWidth + barWidth
        let totalWidth: CGFloat = groupWidth * 2 + groupSpacing
        let totalHeight: CGFloat = 22  // Menu bar height

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocus()

        // Get current appearance for colors
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor.white : NSColor.black
        let barBackgroundColor = isDark ? NSColor.white.withAlphaComponent(0.25) : NSColor.black.withAlphaComponent(0.15)
        let barFillColor = NSColor.systemBlue

        // Draw Session group (label LEFT, bar RIGHT)
        drawGroup(
            label: "S",
            percent: effectiveSession,
            x: 0,
            labelWidth: labelWidth,
            barWidth: barWidth,
            barHeight: barHeight,
            totalHeight: totalHeight,
            textColor: textColor,
            barBackgroundColor: barBackgroundColor,
            barFillColor: barFillColor
        )

        // Draw Week group
        drawGroup(
            label: "W",
            percent: effectiveWeek,
            x: groupWidth + groupSpacing,
            labelWidth: labelWidth,
            barWidth: barWidth,
            barHeight: barHeight,
            totalHeight: totalHeight,
            textColor: textColor,
            barBackgroundColor: barBackgroundColor,
            barFillColor: barFillColor
        )

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func drawGroup(
        label: String,
        percent: Double,
        x: CGFloat,
        labelWidth: CGFloat,
        barWidth: CGFloat,
        barHeight: CGFloat,
        totalHeight: CGFloat,
        textColor: NSColor,
        barBackgroundColor: NSColor,
        barFillColor: NSColor
    ) {
        // Vertical center
        let barY = (totalHeight - barHeight) / 2
        let barX = x + labelWidth

        // Draw label (LEFT side, vertically centered)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        let labelRect = NSRect(x: x, y: barY, width: labelWidth, height: barHeight)
        label.draw(in: labelRect, withAttributes: attributes)

        // Draw bar outline (hollow background, no rounded corners)
        let bgRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)
        let bgPath = NSBezierPath(rect: bgRect)
        barBackgroundColor.setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()

        // Draw filled portion (from bottom to top, no rounded corners)
        let fillHeight = barHeight * CGFloat(min(max(percent, 0), 100)) / 100
        if fillHeight > 0 {
            let fillRect = NSRect(x: barX, y: barY, width: barWidth, height: fillHeight)
            let fillPath = NSBezierPath(rect: fillRect)
            barFillColor.setFill()
            fillPath.fill()
        }
    }
}

/// Legacy icon view for fallback.
/// Uses theme's `statusBarIconName` if set, otherwise shows status-based icons.
struct StatusBarIcon: View {
    let status: QuotaStatus

    @Environment(\.appTheme) private var theme

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(iconColor)
    }

    private var iconName: String {
        // Use theme's custom icon if provided
        if let themeIcon = theme.statusBarIconName {
            return themeIcon
        }
        // Otherwise use status-based icon
        switch status {
        case .depleted:
            return "chart.bar.xaxis"
        case .critical:
            return "exclamationmark.triangle.fill"
        case .warning, .healthy:
            return "chart.bar.fill"
        }
    }

    private var iconColor: Color {
        theme.statusColor(for: status)
    }
}

// MARK: - StatusBarLabel Preview

#Preview("StatusBarLabel - Various States") {
    VStack(spacing: 20) {
        HStack(spacing: 30) {
            VStack {
                StatusBarLabel(sessionPercent: 100, weekPercent: 100)
                Text("Full")
                    .font(.caption)
            }
            VStack {
                StatusBarLabel(sessionPercent: 82, weekPercent: 93)
                Text("Normal")
                    .font(.caption)
            }
            VStack {
                StatusBarLabel(sessionPercent: 30, weekPercent: 45)
                Text("Warning")
                    .font(.caption)
            }
            VStack {
                StatusBarLabel(sessionPercent: 5, weekPercent: 10)
                Text("Critical")
                    .font(.caption)
            }
            VStack {
                StatusBarLabel(sessionPercent: nil, weekPercent: nil)
                Text("No Data")
                    .font(.caption)
            }
        }
    }
    .padding(40)
    .background(Color.black)
}

// MARK: - StatusBarIcon Preview (Legacy)

#Preview("StatusBarIcon - All States") {
    HStack(spacing: 30) {
        VStack {
            StatusBarIcon(status: .healthy)
            Text("HEALTHY")
                .font(.caption)
                .foregroundStyle(.green)
        }
        VStack {
            StatusBarIcon(status: .warning)
            Text("WARNING")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        VStack {
            StatusBarIcon(status: .critical)
            Text("CRITICAL")
                .font(.caption)
                .foregroundStyle(.red)
        }
        VStack {
            StatusBarIcon(status: .depleted)
            Text("DEPLETED")
                .font(.caption)
                .foregroundStyle(.red)
        }
        VStack {
            StatusBarIcon(status: .healthy)
                .appThemeProvider(themeModeId: "cli")
            Text("CLI")
                .font(.caption)
                .foregroundStyle(CLITheme().accentPrimary)
        }
        VStack {
            StatusBarIcon(status: .healthy)
                .appThemeProvider(themeModeId: "christmas")
            Text("CHRISTMAS")
                .font(.caption)
                .foregroundStyle(ChristmasTheme().accentPrimary)
        }
    }
    .padding(40)
    .background(Color.black)
}
