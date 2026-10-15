# Legal & App Store Notes (as of October 2026)

> Not legal advice – a summary of publicly available rules. If the app will be paid, a short check with a
> lawyer specializing in IT/trademark law is worth it.

## 1. Is it OK to build an app for Crafty Controller?

**Yes.** Crafty Controller is open source under **GPL v3 or later**. An app that only talks to the panel via
its HTTP API is a separate program, not a derivative work – the GPL does not extend to your app's code.

Watch out for:
- **Copying code** from the Crafty repo (e.g. JS/HTML from the web panel) → that makes it GPL, and GPL is
  problematic with App Store terms. Write the logic yourself; only use the API.
- **Logo, banners, colors, screenshots of the panel** → don't use them. The license covers the code, not the brand.
  Website: "© Arcadia Technology. All Rights Reserved."

## 2. Name: "Kurafuto"

Apple App Review Guideline **4.1(c)** (since Nov 2025): *You cannot use another developer's icon, brand, or
product name in your app's icon or name without approval from the developer.* Also 5.2.1 (no protected
third-party trademarks without permission, no misleading names/metadata).

This applies to **"Minecraft"** too (Mojang/Microsoft trademark) – not in the name or icon, no creeper/grass-block look.

**Why Kurafuto works:** it is the Japanese transliteration of the generic English word "craft" (クラフト),
not of the brand "Crafty" (クラフティ / "Kurafuti"). We deliberately dropped "Controller" to keep enough
distance from "Crafty Controller".

**Remaining to-dos before release**
- Check trademark registers: **DPMA** (register.dpma.de), **EUIPO TMview**, classes 9 (software) and 42 (SaaS) – to make sure nobody else holds "Kurafuto". Kurafuto itself is not registered (ADR 0008).
- Search the App Store for existing apps named Kurafuto.
- Domain: **getkurafuto.app** (ADR 0006). kurafuto.com belongs to an unrelated personal blog and kurafuto.app is registered by someone else; neither is a competing product.

### Getting found without using the brand name

1. **Ask Arcadia Technology for permission** (info@arcadiatech.org or their Discord). With written approval,
   Guideline 4.1(c) allows "… for Crafty" in the name, and they might link the app from their docs/Discord.
2. **Without permission:** describe compatibility in the description only, e.g.
   *"Compatible with Crafty Controller 4"* plus *"Unofficial app, not affiliated with Arcadia Technology"*.
   This is nominative/descriptive use (in Germany § 23 MarkenG) – usually fine legally, at App Review's discretion.
   **No third-party brands in the keyword field** (Guideline 2.3.7).
3. Visibility outside the store: Reddit r/selfhosted, r/admincraft, the Crafty Discord, a GitHub README –
   there you may say "for Crafty Controller" descriptively.

## 3. Publishing on the App Store from Germany

- **Apple Developer Program**: USD 99/year, available to individuals.
- **EU DSA trader status** (mandatory in App Store Connect for EU storefronts):
  - App **free, no ads/IAP**, hobby project → you can declare yourself a **non-trader**; no address is shown.
  - As soon as you earn money (price, subscription, IAP, ads, tip jar) → **trader** → address, phone and email
    are shown **publicly** in the EU store (alternative: a business address / mailbox service).
  - Without a declaration the app is removed from EU storefronts.
- **Business/tax**: with revenue, register a business (Gewerbe) and handle taxes (check the small-business rule).
  Apple remits VAT on app sales in the EU.
- **Privacy policy**: Apple requires a privacy policy URL for every app. Use
  `https://getkurafuto.app/privacy/` (generated from `PRIVACY.md`, see `site/`). The app talks only to the user's panel,
  stores tokens in the Keychain and has no analytics or third parties (ADR 0002).
  App Privacy label: "Data Not Collected".
- **Legal notice (Impressum)**: required for the support website if the offering is commercial (§ 5 DDG).
  Purely private hobby project without revenue: usually not required – once money flows: yes.
- **Export compliance**: HTTPS/standard crypto only → `ITSAppUsesNonExemptEncryption = false` (already set).

## 4. App Review – typical pitfalls for this kind of app

- **Test account**: Apple needs a working login. Solution: demo mode (built in) **and** a publicly reachable
  test panel with a test user in the review notes.
- **"App is just a website"** (Guideline 4.2): risky if it feels like a web wrapper.
  Native features (widgets, Live Activities, Siri, Face ID) help.
- **Local network**: `NSLocalNetworkUsageDescription` is set – the reason must be clear.
- **Self-signed certificates**: never disable ATS globally; only targeted pinning after user confirmation
  (ADR 0004).
- **"Unofficial" notice** in the description and in the app (shown in Settings).

## Sources

- Crafty Controller website & FAQ – craftycontrol.com
- Crafty docs, OpenAPI v2 – docs.craftycontrol.com/pages/developer-guide/api-reference/
- License GPL v3 or later – gitlab.com/crafty-controller/crafty-4
- Apple App Review Guidelines 4.1, 5.2 – developer.apple.com/app-store/review/guidelines/
- DSA trader status – developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
