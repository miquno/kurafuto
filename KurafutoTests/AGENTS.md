# KurafutoTests/

Unit tests (XCTest). They run against `MockCraftyService` and pure helpers; no test may reach the network.

- Cover decoding quirks with real-looking JSON from the Crafty API (string numbers, `players` as a string literal).
- Use `MockCraftyService(latency: .zero)` for speed. Keep timing-based tests short and deterministic.
- When a model or parser changes, add a focused test in the same pull request.
- Run one slice: `-only-testing:KurafutoTests/MockServiceTests`.
