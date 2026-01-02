import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("AntigravityProvider Tests")
struct AntigravityProviderTests {

    // Reset the shared settings store before each test
    init() {
        DefaultProviderSettingsStore.shared = InMemoryProviderSettingsStore()
    }

    // MARK: - Identity Tests

    @Test
    func `antigravity provider has correct id`() {
        let mockProbe = MockUsageProbe()
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.id == "antigravity")
    }

    @Test
    func `antigravity provider has correct name`() {
        let mockProbe = MockUsageProbe()
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.name == "Antigravity")
    }

    @Test
    func `antigravity provider has correct cliCommand`() {
        let mockProbe = MockUsageProbe()
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.cliCommand == "antigravity")
    }

    @Test
    func `antigravity provider has no dashboard URL because it is local only`() {
        let mockProbe = MockUsageProbe()
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.dashboardURL == nil)
    }

    @Test
    func `antigravity provider has no status page URL because it is local only`() {
        let mockProbe = MockUsageProbe()
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.statusPageURL == nil)
    }

    @Test
    func `antigravity provider is enabled by default`() {
        let mockProbe = MockUsageProbe()
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.isEnabled == true)
    }

    // MARK: - State Tests

    @Test
    func `antigravity provider starts with no snapshot`() {
        let mockProbe = MockUsageProbe()
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.snapshot == nil)
    }

    @Test
    func `antigravity provider starts not syncing`() {
        let mockProbe = MockUsageProbe()
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.isSyncing == false)
    }

    @Test
    func `antigravity provider starts with no error`() {
        let mockProbe = MockUsageProbe()
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.lastError == nil)
    }

    // MARK: - Delegation Tests

    @Test
    func `antigravity provider delegates isAvailable to probe`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let antigravity = AntigravityProvider(probe: mockProbe)

        let isAvailable = await antigravity.isAvailable()

        #expect(isAvailable == true)
    }

    @Test
    func `antigravity provider delegates isAvailable false to probe`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(false)
        let antigravity = AntigravityProvider(probe: mockProbe)

        let isAvailable = await antigravity.isAvailable()

        #expect(isAvailable == false)
    }

    @Test
    func `antigravity provider delegates refresh to probe`() async throws {
        let expectedSnapshot = UsageSnapshot(
            providerId: "antigravity",
            quotas: [UsageQuota(percentRemaining: 95, quotaType: .session, providerId: "antigravity", resetText: "Resets in 1 hour")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let antigravity = AntigravityProvider(probe: mockProbe)

        let snapshot = try await antigravity.refresh()

        #expect(snapshot.providerId == "antigravity")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 95)
    }

    // MARK: - Snapshot Storage Tests

    @Test
    func `antigravity provider stores snapshot after refresh`() async throws {
        let expectedSnapshot = UsageSnapshot(
            providerId: "antigravity",
            quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "antigravity")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.snapshot == nil)

        _ = try await antigravity.refresh()

        #expect(antigravity.snapshot != nil)
        #expect(antigravity.snapshot?.quotas.first?.percentRemaining == 80)
    }

    @Test
    func `antigravity provider clears error on successful refresh`() async throws {
        // Use two separate probes to simulate the behavior
        let failingProbe = MockUsageProbe()
        given(failingProbe).probe().willThrow(ProbeError.timeout)
        let antigravityWithFailingProbe = AntigravityProvider(probe: failingProbe)

        do {
            _ = try await antigravityWithFailingProbe.refresh()
        } catch {
            // Expected
        }
        #expect(antigravityWithFailingProbe.lastError != nil)

        // Create new provider with succeeding probe
        let succeedingProbe = MockUsageProbe()
        let snapshot = UsageSnapshot(providerId: "antigravity", quotas: [], capturedAt: Date())
        given(succeedingProbe).probe().willReturn(snapshot)
        let antigravityWithSucceedingProbe = AntigravityProvider(probe: succeedingProbe)

        _ = try await antigravityWithSucceedingProbe.refresh()

        #expect(antigravityWithSucceedingProbe.lastError == nil)
    }

    // MARK: - Error Handling Tests

    @Test
    func `antigravity provider stores error on refresh failure`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.executionFailed("Server not found"))
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.lastError == nil)

        do {
            _ = try await antigravity.refresh()
        } catch {
            // Expected
        }

        #expect(antigravity.lastError != nil)
    }

    @Test
    func `antigravity provider rethrows probe errors`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.executionFailed("Server not found"))
        let antigravity = AntigravityProvider(probe: mockProbe)

        await #expect(throws: ProbeError.executionFailed("Server not found")) {
            try await antigravity.refresh()
        }
    }

    // MARK: - Syncing State Tests

    @Test
    func `antigravity provider resets isSyncing after refresh completes`() async throws {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(UsageSnapshot(
            providerId: "antigravity",
            quotas: [],
            capturedAt: Date()
        ))
        let antigravity = AntigravityProvider(probe: mockProbe)

        #expect(antigravity.isSyncing == false)

        _ = try await antigravity.refresh()

        #expect(antigravity.isSyncing == false)
    }

    @Test
    func `antigravity provider resets isSyncing after refresh fails`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.timeout)
        let antigravity = AntigravityProvider(probe: mockProbe)

        do {
            _ = try await antigravity.refresh()
        } catch {
            // Expected
        }

        #expect(antigravity.isSyncing == false)
    }

    // MARK: - Uniqueness Tests

    @Test
    func `antigravity provider has unique id compared to other providers`() {
        let mockProbe = MockUsageProbe()
        let antigravity = AntigravityProvider(probe: mockProbe)
        let claude = ClaudeProvider(probe: mockProbe)
        let codex = CodexProvider(probe: mockProbe)
        let gemini = GeminiProvider(probe: mockProbe)
        let copilot = CopilotProvider(probe: mockProbe)

        let ids = Set([antigravity.id, claude.id, codex.id, gemini.id, copilot.id])
        #expect(ids.count == 5) // All unique
    }
}
