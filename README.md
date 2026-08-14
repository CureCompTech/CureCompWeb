# CureComp Technology — Website

Static marketing site for **CureComp Technology** (Reg. 201603089199 / NS0161352-H),
Seremban, Negeri Sembilan. Built on **Bootstrap 5.3** with a red dark theme.

The published site is plain static HTML — no framework, no bundler, nothing to compile.

## Pages

| File | Menu item | Purpose |
| --- | --- | --- |
| `index.html` | Home | Overview of all five practices, client highlights |
| `shop.html` | Shop | Computers, parts, supplies, service & repair |
| `managed-it.html` | Managed IT | MSP services, service tiers, onboarding |
| `network.html` | Networking | Gear from home to ISP-grade, fq_codel QoS, Wi-Fi 6/7, FTTR, fibre to the desk, NAS, NOC |
| `wifi-6-7.html` | *(footer only)* | Deep-dive lesson on the Wi-Fi 6/7 PHY, with animated SVG diagrams |
| `cloud.html` | Cloud | Dedicated servers, colocation, VM/LXC, IPv6 allocation |
| `pon-stick.html` | PON Stick | Anime4000 GPON Stick, NIJIKA SDK, Open PON Foundation, Prometheus/Grafana, MikroTik |
| `about.html` | About Us | Company profile, registration details, full client list (`#clients`) |
| `contact.html` | Contact | Contact methods, Google Map, enquiry form |

## Structure

```
sitemap.xml                  generated
robots.txt                   generated
assets/
  css/theme.css              red dark theme layered over Bootstrap
  js/main.js                 sticky nav, reveals, counters, enquiry form
  img/
    cc_logo-full-wide.svg          original (dark ink — for light backgrounds)
    cc_logo-full-wide-dark.svg     white variant, used in the header and footer
    cc_logo-only-squaree.svg       original icon
    cc_logo-only-squaree-dark.svg  white icon variant
    favicon.svg
    og-cover.png                   1200x630 social preview card (generated)
    apple-touch-icon.png           180x180 iOS icon (generated)
tools/                       page assembly — not part of the published site
  _layout.html               shared head, top bar, navbar and footer
  body-*.html                per-page content
  build.ps1                  writes the eight root pages, sitemap.xml, robots.txt
  make-images.ps1            regenerates og-cover.png and apple-touch-icon.png
  to-tabs.ps1                re-indents the sources with tabs
  link-topics.ps1            points CTAs at their contact-form subject
```

**Indentation is tabs** throughout the HTML, CSS and JS. `tools/to-tabs.ps1` converts
leading spaces to tabs (two spaces per tab) and is safe to re-run — it only touches the
whitespace at the start of a line, never inside text, attributes or `data:` URIs.

## Editing

**Content that lives inside a page** — edit `tools/body-<page>.html`, then rebuild.
**Header, footer, nav, meta tags** — edit `tools/_layout.html` or the page table in
`tools/build.ps1`, then rebuild.

```bash
powershell -ExecutionPolicy Bypass -File tools/build.ps1
```

The root `.html` files are generated output. Editing them directly works, but the next
build overwrites your changes — put edits in `tools/` instead.

> `tools/build.ps1` must keep its **UTF-8 BOM**. Windows PowerShell 5.1 reads a BOM-less
> `.ps1` as ANSI and mangles the em dashes in the page titles. The script now self-checks
> for this and aborts with a clear message rather than publishing corrupted pages, so if
> you ever see *"build.ps1 was parsed as ANSI"*, re-save the file as UTF-8 **with** BOM.
> The same applies to the other `.ps1` files in `tools/`.

## Cache busting

`theme.css` and `main.js` are referenced with a version token so a Cloudflare edge
cache — or a returning visitor's browser — fetches the new file after an upload instead
of serving the old one. Cloudflare keys its cache on the full URL including the query
string, so changing the token is enough; no purge needed.

The token is set by `$assetVersionMode` near the top of `tools/build.ps1`:

| Mode | Output | Notes |
| --- | --- | --- |
| `hash` (default) | `?v=2a0d7b2bac` | Short SHA-256 of that file's own contents. Changes if and only if the file changed, and each asset is versioned separately — editing the CSS does not throw away the cached JS. Nothing to remember. |
| `commit` | `?commit=36fe14c` | Short git SHA of HEAD **at build time**, so it names the commit *before* the one carrying the rebuilt pages. Same token on both files. |
| `manual` | `?version=1.1` | Fixed string from `$assetVersionValue`. You must remember to bump it, or visitors keep the stale file. |

Every build prints the tokens it used. `hash` is the default because it is the only mode
that cannot go stale by forgetting something.

The Bootstrap CDN links need no token — their URLs already carry the version.

## Domains

The site is reachable on three domains:

| Domain | Role |
| --- | --- |
| `curecomp.com.my` | **Canonical.** Every canonical link, `og:url`, `og:image`, JSON-LD `@id` and sitemap entry points here. |
| `curecomp.my` | Alternate — canonicalised to the primary |
| `curecomp.pro` | Alternate — canonicalised to the primary |

Both are set in `tools/build.ps1`: `$siteUrl` for the primary, `$altDomains` for the rest.
The build prints the resulting setup, and refuses to run if an alternate duplicates the
primary or is missing its trailing slash.

**Why the alternates do not get their own canonical URLs.** Three domains serving byte-identical
pages is textbook duplicate content. If each page canonicalised to whichever domain served
it, links and authority would split three ways and Google would pick a winner on its own —
possibly a different one per page. Instead every page carries the *same* canonical
regardless of which domain served it, so all three consolidate onto one. The alternates are
declared in the Organization's `sameAs` so Google ties the domains to the same business
rather than treating them as unrelated sites.

**Add the redirects too.** Canonical tags are a hint; a 301 is a fact, and it also stops
visitors sitting on the wrong hostname. Pick whichever matches your hosting — each rule
only fires when the host is *not* the primary, so it is safe to deploy everywhere:

*Apache — `.htaccess` in the document root*

```apache
RewriteEngine On
RewriteCond %{HTTP_HOST} !^curecomp\.com\.my$ [NC]
RewriteRule ^(.*)$ https://curecomp.com.my/$1 [R=301,L]
```

*nginx — a server block for the alternates*

```nginx
server {
    listen 443 ssl;
    server_name curecomp.my www.curecomp.my curecomp.pro www.curecomp.pro www.curecomp.com.my;
    return 301 https://curecomp.com.my$request_uri;
}
```

*Cloudflare — Rules → Redirect Rules, "single redirect"*

- **If** `http.host ne "curecomp.com.my"`
- **Then** dynamic redirect to `concat("https://curecomp.com.my", http.request.uri.path)`, status **301**, preserve query string.

Add all three domains to Google Search Console. The alternates will report as redirected or
canonicalised — that is the intended result, not an error.

## SEO and social embeds

`$siteUrl` in `tools/build.ps1` is the single source for every absolute URL — canonical
links, `og:url`, `og:image`, Twitter cards, JSON-LD and the sitemap. Social networks will
not fetch a preview image from a relative path, so it must stay absolute and correct.

Each page carries:

- `<title>` under ~60 characters and `<meta name="description">` under ~160, so Google
  shows them whole rather than truncating.
- `<link rel="canonical">`, `robots` with `max-image-preview:large`, and geo meta tags.
- **Open Graph** — used by Facebook, LinkedIn, WhatsApp and Discord.
- **Twitter/X card** — `summary_large_image`.
- `<meta name="theme-color" content="#ed2224">` — this is the accent stripe Discord draws
  beside an embed. It also tints the mobile browser chrome; change it to `#0d0e10` if you
  would rather the address bar match the page background than the brand.
- **JSON-LD** (`schema.org`) for Google: a `LocalBusiness`/`Organization` node with the
  address, phone, geo coordinates, registration number and services, plus `WebSite`,
  `WebPage` and a `BreadcrumbList` on every page except the home page.

`assets/img/og-cover.png` is the 1200×630 preview card, generated by
`tools/make-images.ps1`. It is a plain type-and-logo card — replace it with a designed one
if you have artwork, keeping the same dimensions and filename.

After changing the domain, re-run the build and validate with Facebook's Sharing Debugger,
Twitter's Card Validator and Google's Rich Results Test.

## Running locally

```bash
python -m http.server 8080
```

Then open <http://localhost:8080>. Opening the files directly via `file://` also works.

## Deploying

Upload the repository root to any static host — GitHub Pages, Cloudflare Pages, Netlify,
or an nginx/Apache document root. The `tools/` folder can be excluded; nothing at runtime
reads it.

## Theme notes

- **Dark only.** Red accent taken from the logo (`#ed2224`). Bootstrap runs in
  `data-bs-theme="dark"` and `theme.css` overrides its variables.
- Three reds, split by job so each clears WCAG AA:
  `--cc-red` `#ed2224` graphics and borders, `--cc-red-ink` `#ff5a5c` text and links
  (6.3:1), `--cc-btn` `#d81a1c` button fill under white text (5.1:1). Pure `#ed2224`
  behind white text is only 4.33:1 — that is why the button uses a darker red.
- **Justified text** is deliberately limited to the hero lead paragraph on each page
  (one `.text-justify` per page). Body copy elsewhere is left ragged-right, which reads
  better at narrow column widths. Justification is also switched off below 576px.
- **Label/description lists** use `<dl class="row deflist g-0">` with `dt.col-sm-5` and
  `dd.col-sm-7`, so terms and their descriptions line up as real Bootstrap columns.
  Plain bullet lists still use `<ul class="checks">`.
- `.checks li` is **not** `display: flex`. An inline `<strong>` inside a flex item
  becomes its own flex item, so a bold lead-in breaks out into a second column with the
  rest of the sentence wrapping beside it. The tick is absolutely positioned instead, so
  inline content flows as ordinary text. Don't reintroduce flex there.
- **Hero and CTA backgrounds** size their gradients in percentages, not pixels, so the
  glow covers the full band on 1440p, ultrawide and 4K rather than stopping partway.
- **Tables** use `table-layout: fixed` with `.table-spec` (38% label column) or
  `.table-compare` (28% label column) so values line up in real columns.
- **Reveal animations** are progressive enhancement. Each page head carries
  `<script>document.documentElement.className += " js";</script>` and the hidden start
  state is scoped to `.js .rv`, so a blocked script shows content instead of a blank
  page. `main.js` also reveals everything after 3s if `IntersectionObserver` never fires.
- **Logos**: the supplied SVGs use near-black ink that disappears on the dark background,
  so white variants (`*-dark.svg`) are generated and used throughout. If the source logos
  change, regenerate them by replacing `#010101` with `#ffffff`.

## The Wi-Fi lesson page

`wifi-6-7.html` is a deep-dive guide, deliberately **kept out of the top navigation** so
the main menu stays a list of services. It is reached from the "click to learn more" link
in `network.html#wifi` and from the **Learn** group in the footer. Its `nav` key is
`network`, so the Networking menu item stays highlighted while a visitor reads it, and its
breadcrumb is three levels: Home › Networking › Wi-Fi 6 & 7 explained. Any page can get a
third breadcrumb level by setting `parentCrumb` and `parentOut` in `tools/build.ps1`.

The six diagrams are inline SVG animated with CSS keyframes in `theme.css` (section 24) —
no JavaScript and no external library. Two rules matter when editing them:

- **Every figure must read correctly with the animation stopped.** The reduced-motion
  media query sets `animation: none`, so the authored attribute values *are* the still
  frame. Where a stopped frame would lose the point, add a reduced-motion-only nudge —
  `.phy-rest-ahead` does this for the BSS Coloring diagram, which would otherwise show
  both lanes identical.
- Labels sitting on top of a coloured block use `.t-on` (white), because the block may be
  red or grey depending on where the animation is.

## CTA deep-linking

Every call-to-action points at `contact.html?topic=<slug>#enquiry`. On load, `main.js`
matches the slug against the `data-topic` attribute on each `<option>` in `#f-topic` and
preselects it, so a visitor arriving from the NAS section lands with "NAS / private file
storage" already chosen. Unknown or missing slugs are ignored and the dropdown stays on
its placeholder.

To add a subject: add an `<option data-topic="my-slug">` in `tools/body-contact.html`,
then link to `contact.html?topic=my-slug#enquiry`. `tools/link-topics.ps1` applies the
page-level defaults in bulk and is safe to re-run.

## Enquiry form

Client-side only. It composes a message and hands it to WhatsApp
(`wa.me/60178774376`) or the visitor's mail client (`curecomp@outlook.com`). Nothing is
posted or stored. Swap in a backend or form service if you want submissions captured
server-side.

## Content that needs your confirmation

Written as sensible placeholders — check these against how the business actually runs:

- Service-tier table on `managed-it.html` (Essential / Business / Critical)
- Custom build tiers on `shop.html` (Essential / Creator / Powerhouse)
- Repair workflow steps and on-site coverage areas
- The Open PON Foundation copy on `pon-stick.html` — membership is stated as given, but
  the description of what the Foundation stands for, and the alignment with ONF, EFF and
  the Linux Foundation, is written as a shared-vision statement. A disclaimer notes that
  no endorsement by those three organisations is implied. Replace with the Foundation's
  own wording if it has any.
- Wi-Fi and networking claims on `network.html` (survey process, ISP relationships)
- Business/opening hours are deliberately not stated anywhere; add them if you want them
