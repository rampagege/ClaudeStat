# ClaudeBar Design Guide

## Overview

ClaudeBar is a macOS 15+ menu bar application for monitoring AI coding assistant usage quotas (Claude, Codex, Gemini). Built with TDD, DDD/Clean Architecture, and rich domain models.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        App Layer                             │
│  SwiftUI Views directly expose domain capabilities           │
│  (No ViewModels - rich domain models handle logic)           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                            │
│  Rich Models: UsageQuota, UsageSnapshot, QuotaStatus         │
│  Ports: UsageProbePort, QuotaObserverPort (@Mockable)        │
│  Services: QuotaMonitor (Actor)                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Infrastructure Layer                        │
│  Technical implementations: PTYCommandRunner, ClaudeUsageProbe│
│  Adapters implement domain ports                             │
└─────────────────────────────────────────────────────────────┘
```

## Module Structure

```
ClaudeBar/
├── Package.swift
├── Sources/
│   ├── Domain/                    # Pure business logic
│   │   ├── Models/
│   │   │   ├── AIProvider.swift   # Provider enum with metadata
│   │   │   ├── UsageQuota.swift   # Rich quota model
│   │   │   ├── QuotaType.swift    # Session/Weekly/Model types
│   │   │   ├── QuotaStatus.swift  # Health status with thresholds
│   │   │   └── UsageSnapshot.swift # Aggregate root
│   │   ├── Ports/
│   │   │   ├── UsageProbePort.swift     # @Mockable CLI interface
│   │   │   └── QuotaObserverPort.swift  # @Mockable observer
│   │   └── Services/
│   │       └── QuotaMonitor.swift # Actor-based coordinator
│   │
│   ├── Infrastructure/            # Technical implementations
│   │   └── CLI/
│   │       ├── PTYCommandRunner.swift   # PTY execution
│   │       └── ClaudeUsageProbe.swift   # Claude CLI adapter
│   │
│   └── App/                       # SwiftUI application
│       ├── ClaudeBarApp.swift
│       └── Views/
│           ├── MenuContentView.swift
│           ├── ProviderSectionView.swift
│           └── QuotaCardView.swift
│
└── Tests/
    ├── DomainTests/
    │   ├── Models/
    │   └── Services/
    └── InfrastructureTests/
        └── CLI/
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
public protocol UsageProbePort: Sendable {
    var provider: AIProvider { get }
    func probe() async throws -> UsageSnapshot
    func isAvailable() async -> Bool
}

// Infrastructure Adapter
public struct ClaudeUsageProbe: UsageProbePort {
    public let provider: AIProvider = .claude

    public func probe() async throws -> UsageSnapshot {
        // Technical implementation with PTY
    }
}
```

### 5. Actor-Based Services

Domain services use Swift actors for thread safety:

```swift
public actor QuotaMonitor {
    private let probes: [any UsageProbePort]
    private var snapshots: [AIProvider: UsageSnapshot] = [:]

    public func refreshAll() async throws -> [AIProvider: UsageSnapshot] {
        // Concurrent refresh with structured concurrency
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
    let mockProbe = MockUsageProbePort()
    let mockObserver = MockQuotaObserverPort()
    given(mockProbe).provider.willReturn(.claude)
    ...

    // When - Action
    _ = try await monitor.refreshAll()

    // Then - Assertion
    verify(mockObserver).onStatusChanged(...).called(.once)
}
```

### Mockable Protocols

Use `@Mockable` for all ports:

```swift
@Mockable
public protocol UsageProbePort: Sendable {
    // ...
}

// In tests:
let mockProbe = MockUsageProbePort()
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

1. **Multi-provider support** - Claude, Codex, and Gemini probes implemented
2. **Auto-refresh** - `startMonitoring(interval:)` returns `AsyncStream<MonitoringEvent>`
3. **System notifications** - `NotificationQuotaObserver` alerts on status degradation
4. **Shared app state** - `@Observable AppState` for reactive UI updates

## Next Steps

1. **Add preferences UI** - Settings for refresh interval, enabled providers
2. **Configure Sparkle** - Add appcast URL for auto-updates
3. **Add keyboard shortcuts** - Quick refresh, open dashboard
4. **Add login helpers** - Prompt to login when auth required
