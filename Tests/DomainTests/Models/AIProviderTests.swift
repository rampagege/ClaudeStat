import Testing
@testable import Domain

@Suite
struct AIProviderTests {

    // MARK: - Provider Identity

    @Test
    func `claude provider has correct name and cli command`() {
        // Given
        let provider = AIProvider.claude

        // When & Then
        #expect(provider.name == "Claude")
        #expect(provider.cliCommand == "claude")
        #expect(provider.isEnabled == true)
    }

    @Test
    func `codex provider has correct name and cli command`() {
        // Given
        let provider = AIProvider.codex

        // When & Then
        #expect(provider.name == "Codex")
        #expect(provider.cliCommand == "codex")
        #expect(provider.isEnabled == true)
    }

    @Test
    func `gemini provider has correct name and cli command`() {
        // Given
        let provider = AIProvider.gemini

        // When & Then
        #expect(provider.name == "Gemini")
        #expect(provider.cliCommand == "gemini")
        #expect(provider.isEnabled == true)
    }

    @Test
    func `all providers can be enumerated`() {
        // Given & When
        let allProviders = AIProvider.allCases

        // Then
        #expect(allProviders.count == 3)
        #expect(allProviders.contains(.claude))
        #expect(allProviders.contains(.codex))
        #expect(allProviders.contains(.gemini))
    }

    // MARK: - Dashboard Links

    @Test
    func `claude links to anthropic billing dashboard`() {
        // Given
        let provider = AIProvider.claude

        // When & Then
        #expect(provider.dashboardURL?.absoluteString == "https://console.anthropic.com/settings/billing")
    }

    @Test
    func `codex links to openai usage dashboard`() {
        // Given
        let provider = AIProvider.codex

        // When & Then
        #expect(provider.dashboardURL?.absoluteString == "https://chatgpt.com/codex/settings/usage")
    }
}
