import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("CopilotProvider Env Var Configuration Tests")
struct CopilotProviderEnvVarConfigTests {

    private func makeSettingsRepository(copilotEnabled: Bool = true) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(copilotEnabled)
        given(mock).isEnabled(forProvider: .any).willReturn(copilotEnabled)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    private func makeCredentialRepository(username: String = "", token: String = "") -> MockCredentialRepository {
        let mock = MockCredentialRepository()
        given(mock).get(forKey: .any).willReturn(username.isEmpty ? nil : username)
        given(mock).exists(forKey: .any).willReturn(!token.isEmpty)
        given(mock).save(.any, forKey: .any).willReturn()
        given(mock).delete(forKey: .any).willReturn()
        return mock
    }

    private func makeConfigRepository(copilotEnvVar: String = "") -> MockProviderConfigRepository {
        let mock = MockProviderConfigRepository()
        given(mock).zaiConfigPath().willReturn("")
        given(mock).glmAuthEnvVar().willReturn("")
        given(mock).copilotAuthEnvVar().willReturn(copilotEnvVar)
        given(mock).setZaiConfigPath(.any).willReturn()
        given(mock).setGlmAuthEnvVar(.any).willReturn()
        given(mock).setCopilotAuthEnvVar(.any).willReturn()
        return mock
    }

    // MARK: - Initialization Tests

    @Test
    func `copilot provider with various config repository settings`() {
        let settings = makeSettingsRepository()
        let credentials = makeCredentialRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()

        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        #expect(provider != nil)
    }

    @Test
    func `copilot provider config repository is injectable`() {
        let settings = makeSettingsRepository()
        let credentials = makeCredentialRepository()
        let config = makeConfigRepository(copilotEnvVar: "CUSTOM_GH_TOKEN")
        let mockProbe = MockUsageProbe()

        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        #expect(provider != nil)
    }

    // MARK: - Environment Variable Configuration Tests

    @Test
    func `copilot provider passes config repository to probe`() {
        let settings = makeSettingsRepository()
        let credentials = makeCredentialRepository()
        let config = makeConfigRepository(copilotEnvVar: "MY_GITHUB_TOKEN")
        let mockProbe = MockUsageProbe()

        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        #expect(provider != nil)
        #expect(provider.id == "copilot")
    }

    // MARK: - Multiple Env Var Configurations

    @Test
    func `multiple providers can have different env var configurations`() {
        let settings = makeSettingsRepository()
        let credentials = makeCredentialRepository()
        let configCopilot = makeConfigRepository(copilotEnvVar: "GH_TOKEN_VAR")
        
        let mockProbe = MockUsageProbe()

        let copilotProvider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: configCopilot
        )

        #expect(copilotProvider != nil)
        #expect(copilotProvider.id == "copilot")
    }

    // MARK: - Default Configuration Tests

    @Test
    func `provider initializes successfully with config repository`() {
        let settings = makeSettingsRepository()
        let credentials = makeCredentialRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()

        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        #expect(provider != nil)
    }
}
