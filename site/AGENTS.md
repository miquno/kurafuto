# site/

The static website served at **https://getkurafuto.app** via GitHub Pages (`.github/workflows/pages.yml`). Plain HTML and one stylesheet; no build step.

| File | Purpose |
|---|---|
| `index.html` | Landing page |
| `privacy/index.html` | Privacy policy – the App Store privacy policy URL |
| `404.html` | Not-found page |
| `styles.css`, `icon.svg` | Shared style and icon |
| `CNAME` | Custom domain for GitHub Pages |

## Rules

- `privacy/index.html` mirrors `PRIVACY.md`. Change both in the same pull request.
- No JavaScript, cookies, analytics, web fonts, CDNs, embeds or images from other hosts. Every page keeps the CSP meta tag (`default-src 'none'`) and `referrer: no-referrer`.
- Light and dark mode via `prefers-color-scheme`; pages must stay readable at 320 px width and 200 % zoom.
- Animations are CSS only and live inside `@media (prefers-reduced-motion: no-preference)`; without them every page must look finished. Japanese ornaments use system Mincho fonts and are `aria-hidden`.
- Adding anything that loads from another origin needs an ADR and updates to `PRIVACY.md` and the threat model.
