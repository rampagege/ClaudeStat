# ClaudeBar Design Guide

## Overview

ClaudeBar is a macOS 15+ menu bar application for monitoring AI coding assistant usage quotas (Claude, Codex, Gemini). Built with TDD, DDD/Clean Architecture, and rich domain models.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        App Layer                             │
│  SwiftUI Views consume QuotaMonitor directly + StatusBarIcon │
│  (No ViewModels, no AppState - rich domain models)           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                            │
│  Rich Models: UsageQuota, UsageSnapshot, QuotaStatus         │
│  Ports: UsageProbe (ProbeError), QuotaStatusListener         │
│  Services: QuotaMonitor (@Observable + AsyncStream)          │
│  Repository: AIProviders (manages provider collection)       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Infrastructure Layer                        │
│  CLI: Claude, Codex (RPC), Gemini (CLI+API)                  │
│  Adapters: PTY, Process, URLSession | Notifications          │
└─────────────────────────────────────────────────────────────┘
```

## Module Structure

```
ClaudeBar/
├── Package.swift
├── Sources/
│   ├── Domain/                    # Pure business logic
│   │   ├── Monitor/
│   │   │   ├── QuotaMonitor.swift        # Actor + MonitoringEvent + AsyncStream
│   │   │   └── StatusChangeObserver.swift # Protocol for status notifications
│   │   └── Provider/
│   │       ├── AIProvider.swift          # Protocol + UsageProbe protocol
│   │       ├── UsageQuota.swift          # Rich quota model
│   │       ├── QuotaType.swift           # Session/Weekly/Model types
│   │       ├── QuotaStatus.swift         # Health status with thresholds
│   │       ├── UsageSnapshot.swift       # Aggregate root
│   │       ├── ProbeError.swift          # Error types
│   │       └── ... (Concrete Providers like ClaudeProvider.swift)
│   │
    ├── Infrastructure/            # Technical implementations
│   │   ├── Adapters/              # Low-level system adapters (excluded from coverage)
│   │   │   ├── PTYCommandRunner.swift      # PTY execution wrapper
│   │   │   ├── ProcessRPCTransport.swift   # JSON-RPC over stdin/stdout
│   │   │   └── ...
│   │   ├── CLI/                   # CLI Probes and Logic
│   │   │   ├── ClaudeUsageProbe.swift      # Claude probe
│   │   │   ├── CodexUsageProbe.swift       # Codex probe (uses RPCClient)
│   │   │   ├── DefaultCodexRPCClient.swift # RPC client logic
│   │   │   ├── CLIExecutor.swift           # Protocol for CLI execution
│   │   │   ├── RPCTransport.swift          # Protocol for RPC communication
│   │   │   ├── GeminiUsageProbe.swift      # Gemini probe coordinator
│   │   │   ├── GeminiCLIProbe.swift        # Gemini CLI probe
│   │   │   ├── GeminiAPIProbe.swift        # Gemini API probe
│   │   │   └── GeminiProjectRepository.swift # Project discovery
│   │   ├── Network/
│   │   │   └── NetworkClient.swift         # @Mockable HTTP abstraction
│   │   └── Notifications/
│   │       └── NotificationQuotaObserver.swift # macOS notifications
│   │
│   └── App/                       # SwiftUI application
│       ├── ClaudeBarApp.swift     # Entry point + QuotaMonitor
│       └── Views/
│           ├── MenuContentView.swift
│           ├── ProviderSectionView.swift
│           ├── QuotaCardView.swift
│           └── StatusBarIcon.swift
│
└── Tests/
    ├── DomainTests/
    │   ├── Monitor/
    │   └── Provider/
    └── InfrastructureTests/
        ├── CLI/
        └── Notifications/
```

## Design Principles

### 1. Rich Domain Models

Domain models contain business logic, not just data:

```swift
public struct UsageQuota {
    public let percentRemaining: Double
    public let quotaType: QuotaType

    // Business logic in the model
    public var status: QuotaStatus {
        QuotaStatus.from(percentRemaining: percentRemaining)
    }

    public var isDepleted: Bool {
        percentRemaining <= 0
    }

    public var needsAttention: Bool {
        status.needsAttention
    }
}
```

### 2. Domain-Driven Terminology

Use domain language, not technical terms:

| Domain Term | Technical Term |
|-------------|----------------|
| `UsageQuota` | `UsageData` |
| `QuotaStatus` | `HealthStatus` |
| `AIProvider` | `ServiceProvider` |
| `UsageSnapshot` | `UsageDataResponse` |
| `QuotaMonitor` | `UsageDataFetcher` |

### 3. No ViewModel Layer

UI directly uses rich domain models:

```swift
struct QuotaCardView: View {
    let quota: UsageQuota  // Domain model directly

    var body: some View {
        Text("\(Int(quota.percentRemaining))%")
            .foregroundStyle(quota.status.displayColor)  // Rich model
    }
}
```

### 4. Ports and Adapters

Domain defines interfaces, infrastructure implements:

```swift
// Domain Port
@Mockable
public protocol UsageProbe: Sendable {
    func probe() async throws -> UsageSnapshot
    func isAvailable() async -> Bool
}

// Infrastructure Adapter
public struct ClaudeUsageProbe: UsageProbe {
    public func probe() async throws -> UsageSnapshot {
        // Technical implementation with PTY
    }
}
```

### 5. @Observable Services with Repository

Domain services use `@Observable` for SwiftUI reactivity with `AIProviders` repository:

```swift
@Observable
public final class QuotaMonitor: @unchecked Sendable {
    private let providers: AIProviders  // Repository
    public var selectedProviderId: String = "claude"

    public var overallStatus: QuotaStatus {
        providers.enabled.compactMap(\.snapshot?.overallStatus).max() ?? .healthy
    }

    public func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers.enabled {
                group.addTask { await self.refreshProvider(provider) }
            }
        }
    }
}
```

## Testing Conventions

### Test Naming

Use backtick syntax with user-focused descriptions:

```swift
@Test
func `quota with more than 50 percent remaining is healthy`() {
    // Given
    let quota = UsageQuota(percentRemaining: 65, quotaType: .session, provider: .claude)

    // When & Then
    #expect(quota.status == .healthy)
}
```

### Given-When-Then Structure

All tests follow this pattern:

```swift
@Test
func `monitor notifies observer when status changes`() async throws {
    // Given - Setup
    let mockProbe = MockUsageProbe()
    let mockObserver = MockStatusChangeObserver()
    
    // Setup mock probe
    given(mockProbe).probe().willReturn(UsageSnapshot(...))
    given(mockProbe).isAvailable().willReturn(true)
    
    let provider = ClaudeProvider(probe: mockProbe)
    let monitor = QuotaMonitor(providers: [provider], statusObserver: mockObserver)

    // When - Action
    await monitor.refreshAll()

    // Then - Assertion
    verify(mockObserver).onStatusChanged(providerId: .any, oldStatus: .any, newStatus: .any).called(.once)
}
```

### Mockable Protocols

Use `@Mockable` for all ports:

```swift
@Mockable
public protocol UsageProbe: Sendable {
    // ...
}

// In tests:
let mockProbe = MockUsageProbe()
given(mockProbe).probe().willReturn(snapshot)
verify(mockProbe).probe().called(.once)
```

## Status Thresholds

Business rules encoded in domain:

| Percentage Remaining | Status |
|---------------------|--------|
| > 50% | `.healthy` |
| 20-50% | `.warning` |
| < 20% | `.critical` |
| 0% | `.depleted` |

## Snapshot Freshness

- Fresh: < 5 minutes old
- Stale: >= 5 minutes old

## Dependencies

- **Mockable**: Protocol mocking for tests
- **Sparkle**: Auto-update functionality
- **Swift Testing**: Modern test framework

## Implemented Features

1. **Multi-provider support** - Claude, Codex, Gemini, Copilot, Antigravity, Z.ai probes
2. **Auto-refresh** - `startMonitoring(interval:)` returns `AsyncStream<MonitoringEvent>`
3. **System notifications** - `QuotaAlerter` alerts on status degradation
4. **Enable/disable providers** - Each provider has `isEnabled` state persisted to UserDefaults
5. **Provider selection** - UI can select and display individual provider quotas

## Next Steps

1. **Add preferences UI** - Settings for refresh interval, enabled providers
2. **Configure Sparkle** - Add appcast URL for auto-updates
3. **Add keyboard shortcuts** - Quick refresh, open dashboard
4. **Add login helpers** - Prompt to login when auth required
