# 0004. Trust self-signed panels by explicit certificate pinning

- Status: Accepted
- Date: 2026-10-14

## Context

Crafty Controller serves HTTPS with a self-signed certificate by default. iOS rejects such certificates, which is why the official PWA needs a CA-signed certificate. Disabling App Transport Security or accepting any certificate would expose tokens to man-in-the-middle attacks.

## Decision

- Certificates that pass system trust (e.g. Let's Encrypt behind a reverse proxy) are used normally.
- For a self-signed certificate, the connection is cancelled and the SHA-256 fingerprint of the leaf certificate is shown to the user. Only after explicit confirmation is the fingerprint stored with the panel and accepted for that panel only.
- App Transport Security stays enabled; no `NSAllowsArbitraryLoads`, no `NSAllowsLocalNetworking`, no plain HTTP.

## Alternatives considered

- **Accept all certificates for local IPs** – rejected: silent MITM on shared networks.
- **Require a CA certificate (like the PWA)** – rejected: excludes the default Crafty setup.

## Consequences

A certificate change on the panel (e.g. regeneration) breaks the connection until the user re-confirms the new fingerprint. This is intended. A UI to review and reset pinned fingerprints is part of 0.2.
