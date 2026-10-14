# 0006. Website on getkurafuto.app via GitHub Pages

- Status: Accepted
- Date: 2026-10-14

## Context

The App Store requires a privacy policy URL and a support URL. A support email must not expose a private address. kurafuto.com and kurafuto.app are already registered by others; "Kurafuty" and similar spellings were rejected because they sound like "Crafty" (ADR 0005).

## Decision

- Domain: **getkurafuto.app**. The `.app` TLD is on the HSTS preload list, so the site is HTTPS-only by default. WHOIS data stays redacted at the registrar.
- The website is plain static HTML in `site/`, deployed to GitHub Pages by `.github/workflows/pages.yml`. No JavaScript, cookies, analytics, web fonts, CDNs or embeds; every page carries a restrictive CSP meta tag and `referrer: no-referrer`.
- `site/privacy/index.html` mirrors `PRIVACY.md` and is the App Store privacy policy URL. Support contact is `support@getkurafuto.app`, forwarded to the maintainer.
- The app links to the website and privacy policy from Settings; opening them is a user action in Safari, not a request made by the app.

## Alternatives considered

- **Privacy policy only on github.com** – works, but ties the store listing to a repository path and looks less trustworthy to users.
- **Hosted site builder** – rejected: adds cookies, analytics or third-party scripts by default.
- **Cloudflare Pages** – equivalent; GitHub Pages keeps everything in one place with the repository.

## Consequences

GitHub processes visitor IP addresses to serve the site; this is disclosed in `PRIVACY.md`. Changing the domain means updating `site/CNAME`, `AppLinks` in `SettingsView.swift`, `PRIVACY.md`, the website and the store listing together.
