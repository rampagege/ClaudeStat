# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClaudeBar is a macOS menu bar application that monitors AI coding assistant usage quotas (Claude, Codex, Gemini). It probes CLI tools to fetch quota information and displays it in a menu bar interface with system notifications for status changes.

## Build & Test Commands

```bash
# Build the project
swift build

# Run all tests
swift test

# Run a specific test file
swift test --filter DomainTests

# Run a specific test
swift test --filter "QuotaMonitorTests/monitor fetches usage from a single provider"

# Run the app (requires macOS 15+)
swift run ClaudeBar
```

## Architecture

The project follows a clean architecture with hexagonal/ports-and-adapters patterns:

### Layers

- **Domain** (`Sources/Domain/`): Pure business logic with no external dependencies
  - Provider (`Provider/`): `AIProvider` protocol, `UsageProbe` protocol, and rich models (`UsageQuota`, `UsageSnapshot`, `QuotaStatus`)
  - Monitor (`Monitor/`): `QuotaMonitor` actor and `StatusChangeObserver` protocol

- **Infrastructure** (`Sources/Infrastructure/`): Technical implementations
  - CLI (`CLI/`):
    - `ClaudeUsageProbe` - parses Claude CLI output
    - `CodexUsageProbe` - uses JSON-RPC via `CodexRPCClient`, falls back to TTY
    - `GeminiUsageProbe` - coordinates `GeminiCLIProbe` and `GeminiAPIProbe` strategies
    - `GeminiProjectRepository` - discovers Gemini projects for quota lookup
    - `PTYCommandRunner` - runs CLI commands with PTY for interactive prompts
  - Network (`Network/`): `NetworkClient` protocol for HTTP abstraction
  - Notifications (`Notifications/`): `NotificationQuotaObserver` - macOS notification center

- **App** (`Sources/App/`): SwiftUI menu bar application
  - Views directly consume domain models (no ViewModel layer)
  - `AppState` is an `@Observable` class shared across views
  - `StatusBarIcon` - menu bar icon with status indicator

### Key Patterns

- **Ports and Adapters**: Domain defines ports (`UsageProbe`, `StatusChangeObserver`), infrastructure provides adapters
- **Actor-based concurrency**: `QuotaMonitor` is an actor for thread-safe state management
- **Mockable protocol mocks**: Uses `@Mockable` macro from Mockable package for test doubles
- **Swift Testing framework**: Tests use `@Test` and `@Suite` attributes, not XCTest

### Adding a New AI Provider

1. Create a new provider class implementing `AIProvider` in `Sources/Domain/Provider/`
2. Create probe in `Sources/Infrastructure/CLI/` implementing `UsageProbe`
3. Register provider in `ClaudeBarApp.init()`
4. Add parsing tests in `Tests/InfrastructureTests/CLI/`

## Dependencies

- **Sparkle**: Auto-update framework for macOS
- **Mockable**: Protocol mocking for tests via Swift macros
