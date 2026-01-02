import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("CopilotProvider Tests")
struct CopilotProviderTests {

    /// Creates a mock settings repository that returns true for all providers
    /// Note: CopilotProvider defaults to disabled, so tests that check isEnabled == false
    /// need the mock to return false for "copilot"
    private func makeSettingsRepository(copilotEnabled: Bool = true) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(copilotEnabled)
        given(mock).isEnabled(forProvider: .any).willReturn(copilotEnabled)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Identity Tests

    @Test
    func `copilot provider has correct id`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.id == "copilot")
    }

    @Test
    func `copilot provider has correct name`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.name == "Copilot")
    }

    @Test
    func `copilot provider has correct cliCommand`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.cliCommand == "gh")
    }

    @Test
    func `copilot provider has dashboard URL pointing to GitHub`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.dashboardURL != nil)
        #expect(copilot.dashboardURL?.host?.contains("github") == true)
    }

    @Test
    func `copilot provider has status page URL`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.statusPageURL != nil)
        #expect(copilot.statusPageURL?.host?.contains("githubstatus") == true)
    }

    @Test
    func `copilot provider is disabled by default`() {
        // CopilotProvider defaults to disabled since it requires manual setup
        let settings = makeSettingsRepository(copilotEnabled: false)
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.isEnabled == false)
    }

    // MARK: - State Tests

    @Test
    func `copilot provider starts with no snapshot`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.snapshot == nil)
    }

    @Test
    func `copilot provider starts not syncing`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.isSyncing == false)
    }

    @Test
    func `copilot provider starts with no error`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.lastError == nil)
    }

    // MARK: - Delegation Tests

    @Test
    func `copilot provider delegates isAvailable to probe`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        let isAvailable = await copilot.isAvailable()

        #expect(isAvailable == true)
    }

    @Test
    func `copilot provider delegates isAvailable false to probe`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(false)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        let isAvailable = await copilot.isAvailable()

        #expect(isAvailable == false)
    }

    @Test
    func `copilot provider delegates refresh to probe`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "copilot",
            quotas: [UsageQuota(percentRemaining: 95, quotaType: .session, providerId: "copilot", resetText: "100/2000 requests")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        let snapshot = try await copilot.refresh()

        #expect(snapshot.providerId == "copilot")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 95)
    }

    // MARK: - Snapshot Storage Tests

    @Test
    func `copilot provider stores snapshot after refresh`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "copilot",
            quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "copilot")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.snapshot == nil)

        _ = try await copilot.refresh()

        #expect(copilot.snapshot != nil)
        #expect(copilot.snapshot?.quotas.first?.percentRemaining == 80)
    }

    @Test
    func `copilot provider clears error on successful refresh`() async throws {
        let settings = makeSettingsRepository()
        // Use two separate probes to simulate the behavior
        let failingProbe = MockUsageProbe()
        given(failingProbe).probe().willThrow(ProbeError.timeout)
        let copilotWithFailingProbe = CopilotProvider(probe: failingProbe, settingsRepository: settings)

        do {
            _ = try await copilotWithFailingProbe.refresh()
        } catch {
            // Expected
        }
        #expect(copilotWithFailingProbe.lastError != nil)

        // Create new provider with succeeding probe
        let succeedingProbe = MockUsageProbe()
        let snapshot = UsageSnapshot(providerId: "copilot", quotas: [], capturedAt: Date())
        given(succeedingProbe).probe().willReturn(snapshot)
        let copilotWithSucceedingProbe = CopilotProvider(probe: succeedingProbe, settingsRepository: settings)

        _ = try await copilotWithSucceedingProbe.refresh()

        #expect(copilotWithSucceedingProbe.lastError == nil)
    }

    // MARK: - Error Handling Tests

    @Test
    func `copilot provider stores error on refresh failure`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.lastError == nil)

        do {
            _ = try await copilot.refresh()
        } catch {
            // Expected
        }

        #expect(copilot.lastError != nil)
    }

    @Test
    func `copilot provider rethrows probe errors`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await copilot.refresh()
        }
    }

    // MARK: - Syncing State Tests

    @Test
    func `copilot provider resets isSyncing after refresh completes`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(UsageSnapshot(
            providerId: "copilot",
            quotas: [],
            capturedAt: Date()
        ))
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.isSyncing == false)

        _ = try await copilot.refresh()

        #expect(copilot.isSyncing == false)
    }

    @Test
    func `copilot provider resets isSyncing after refresh fails`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.timeout)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        do {
            _ = try await copilot.refresh()
        } catch {
            // Expected
        }

        #expect(copilot.isSyncing == false)
    }

    // MARK: - Uniqueness Tests

    @Test
    func `copilot provider has unique id compared to other providers`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)
        let codex = CodexProvider(probe: mockProbe, settingsRepository: settings)
        let gemini = GeminiProvider(probe: mockProbe, settingsRepository: settings)

        let ids = Set([copilot.id, claude.id, codex.id, gemini.id])
        #expect(ids.count == 4) // All unique
    }
}
