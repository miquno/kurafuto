# Architecture decision records

An ADR records one significant decision: its context, the decision, the alternatives and the consequences. ADRs are numbered and never renumbered. To change a decision, write a new ADR that supersedes the old one and update the old one's status.

Write an ADR when a change adds a dependency, changes a trust boundary, adds a network peer, introduces a new kind of stored data, or picks between architectural alternatives.

| # | Title | Status |
|---|---|---|
| [0001](0001-native-swiftui-and-xcodegen.md) | Native SwiftUI app generated with XcodeGen, no dependencies | Accepted |
| [0002](0002-no-data-collection.md) | No data collection; the user's panel is the only network peer | Accepted |
| [0003](0003-service-protocol-and-mock-first.md) | `CraftyService` protocol with a full mock | Accepted |
| [0004](0004-self-signed-certificate-pinning.md) | Trust self-signed panels by explicit certificate pinning | Accepted |
| [0005](0005-licence-and-naming.md) | MIT licence and the name "Kurafuto" | Accepted |
| [0006](0006-website-and-domain.md) | Website on getkurafuto.app via GitHub Pages | Accepted |

## Template

```markdown
# NNNN. Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context

## Decision

## Alternatives considered

## Consequences
```
