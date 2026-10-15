# KurafutoTests/

Unit tests (XCTest). They run against `MockCraftyService` and pure helpers; no test may reach the network.

- Cover decoding quirks with real-looking JSON from the Crafty API (string numbers, `players` as a string literal).
- To check what `LiveCraftyService` sends, give its `APIClient` a session configuration with `StubPanel` (in `BackupTests.swift`) as protocol class: it records requests and answers with canned panel responses, offline.
- Use `MockCraftyService(latency: .zero)` for speed. Keep timing-based tests short and deterministic.
- When a model or parser changes, add a focused test in the same pull request.
- Run one slice: `-only-testing:KurafutoTests/MockServiceTests`.
