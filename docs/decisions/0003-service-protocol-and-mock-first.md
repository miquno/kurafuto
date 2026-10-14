# 0003. `CraftyService` protocol with a full mock

- Status: Accepted
- Date: 2026-10-14

## Context

The official Crafty OpenAPI spec is incomplete (no backup, file or WebSocket endpoints), so parts of the live integration need verification. UI work, previews, tests, the demo mode and App Review must not depend on a running panel.

## Decision

Views depend only on the `CraftyService` protocol. `LiveCraftyService` implements it against API v2 and marks each area ✅ documented or ⚠️ unverified. `MockCraftyService` implements the same behavior in memory, including latency, status transitions, a live console and injectable failures.

## Alternatives considered

- **Views call the API client directly** – rejected: untestable, no demo mode.
- **Recorded HTTP fixtures only** – rejected: cannot simulate state changes (start → running).

## Consequences

Every new capability is added to the protocol, the live service and the mock in the same change. The demo mode doubles as the App Review test path.
