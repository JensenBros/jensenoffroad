# Jensen Off-Road — Website Notes & Roadmap

_A planning + reference doc for jensenoffroad.com. Local notes only — no need to upload this file to your host._
_Last updated: June 9, 2026._

---

## 1. How to preview the site right now

**Double-click `Preview Site.bat`.** It starts a small local web server and opens the site in your browser, where the videos play inline exactly like the live site will.

- Keep the little black window open while you browse. Close it to stop.
- **Don't** just double-click `index.html` — opening a file directly can't run YouTube players (you'll see "Error 153"). That's a browser rule, not a bug in the site.

---

## 2. What's built so far

A multi-page static site (plain HTML/CSS/JS — no build step, hosts anywhere):

```
index.html                     Home page (video grid is auto-generated between markers)
styles.css                     Shared styling for every page
site.js                        Shared scripts (mobile menu, year, local-preview fallback)
logo.svg / logo-light.svg      Logos (dark-bg version is logo-light.svg)
videos/                        One dedicated, SEO-optimized page PER video (auto-generated)

build.ps1                      The generator: pulls YouTube -> rebuilds all pages + sitemap
videos.json                    Durable video catalog (source of truth; older videos kept here)
sitemap.xml                    Auto-generated list of pages for Google
.github/workflows/build.yml    The cloud "robot": runs 3x/day + manual button, deploys

Preview Site.bat / serve.ps1   Local preview tool (see section 1)
SETUP — Auto-Updating Site.md  One-time setup guide (host, API key, domain)
Website Notes & Roadmap.md     This file
```

> The `videos/*.html` pages, the home grid, and `sitemap.xml` are all **generated** by `build.ps1` from `videos.json` — don't hand-edit them; edit the catalog or the template in `build.ps1`.

**How it works:** Home page shows 6 video thumbnails → click one → goes to that video's own page on your site → the video **plays inline on the page** (viewer stays on jensenoffroad.com). Each video page also shows a "More from Jensen Off-Road" row to keep people clicking around your site.

**Design:** dark/rugged theme; accent color is your brand red `#ed1c24` (matches the logo). All colors are CSS variables at the top of `styles.css` — change one line, the whole site updates.

---

## 3. Decisions made (and why)

- **Logo:** using the "Jensen Bros. Off-Road" logo from jensenbrosoffroad.com. You're OK with this "for now" even though the domain is jensenoffroad.com. _(Revisit: do you want a wordmark that matches the jensenoffroad.com name?)_
- **Videos play on your site, not YouTube** — to maximize the time visitors spend with you.
- **Kept the standard click-to-play player on purpose** (not an autoplay "facade"). See the monetization note in section 4 — autoplay would cost you views and ad money.
- **Removed the "Watch on YouTube" button** (it shoved viewers into YouTube's feed). Replaced with a "More Jensen videos" button (on-site) and a "Subscribe" link that opens in a **new tab** so your page stays open.
- **SEO:** every video page has a unique title, description, canonical URL, Open Graph/Twitter cards, and **VideoObject structured data** (the schema Google uses for video rich results).
- **Auto-update: BUILT (June 9, 2026).** Periodic check ("polling") — a scheduled cloud job (GitHub Actions, **3× per day** + a manual "Run workflow" button) runs `build.ps1`, which pulls new videos via the **YouTube Data API** (free key), merges them into `videos.json` (older videos never lost), regenerates every page + home grid + sitemap, and deploys to **GitHub Pages**. See **`SETUP — Auto-Updating Site.md`** for the one-time setup. The generator was code-reviewed (multi-agent) and the render path is tested locally; the YouTube-fetch path runs for real on the first GitHub run / when you run `build.ps1` locally with your key.
- **Video hosting: staying with YouTube embeds for now** (decided June 9, 2026). Self-hosting (section 6) is parked as a future option — revisit only if full branding control on a flagship video becomes worth the bandwidth cost and the lost YouTube views/ad revenue.

---

## 4. Verified YouTube facts (researched against official Google docs, June 2026)

Keep these in mind for any future video decisions.

**Embed settings we're using** (on a `youtube-nocookie.com` player):
`?rel=0&playsinline=1&iv_load_policy=3&cc_load_policy=0`
- `playsinline=1` — keeps playback inline on phones (without it, iPhones jump to fullscreen and pull viewers off the page). Most important one.
- `rel=0` — end-of-video suggestions stay limited to **your own** channel (you can't fully remove "related videos" anymore).
- `iv_load_policy=3` — hides clickable cards that link off-page.
- `modestbranding` and similar old tricks are **dead** (removed by YouTube in 2023) — they no longer hide anything.

**Money (this is the key one):**
- A real viewer clicking play on your **embedded** video counts as a true view and earns you the **same ad money** as a view on YouTube itself. Embedding = free reach + same ad revenue, and now it keeps the viewer on your site. Pure win.
- **BUT autoplayed embedded videos do NOT count or earn** — which is exactly why we use standard click-to-play.
- The website owner (you, wearing your "site" hat) doesn't get an extra cut, but Google serves the video bytes for free, so it costs you nothing.

**What we CAN'T do (YouTube Terms of Service):**
- The YouTube logo, the video title/channel watermark, the small "Watch on YouTube" link inside the player, and end-screen suggestions are **baked into the player and cannot be removed**. Hiding them with CSS/overlays is a ToS violation and can get your access limited. We build retention with **your page around the player**, never by tampering with the player.

---

## 5. Still to confirm / finish

- [ ] **Hosting** — no host chosen yet. Needed to actually go live (and for SEO to start working).
- [ ] **Brand name** — logo says "Jensen Bros. Off-Road"; domain is jensenoffroad.com. Keep as-is or make a matching wordmark?
- [ ] **Footer social links** — Instagram and email icons currently point to `#` (placeholders). YouTube link is set. _(Edit in `index.html`, footer section.)_
- [ ] **About section copy** — currently placeholder text. Want to write a real bio?

---

## 6. Next-step options (pick anytime)

| Option | What it does | Effort | Why it matters |
|---|---|---|---|
| **Get it hosted** | Put the site live at jensenoffroad.com | Low–Med | Required for SEO + sharing |
| **"Add a video" generator** | You paste a YouTube link → it builds the SEO page + adds the home card automatically | Med | Big time-saver as you post a lot |
| **sitemap.xml + robots.txt** | Helps Google find/index all video pages faster | Low | Faster SEO results |
| **Self-host a flagship video** | White-label player (no YouTube logo/links) for 1–3 key videos | Med | Full control where it matters most |
| **Analytics** | See what visitors watch and where they go | Low | Know what's working |
| **Auto-refresh latest videos** | Home page pulls your newest uploads automatically | Med–High | Less manual upkeep |

### On self-hosting (for full branding / zero YouTube links)
Only worth it for a few flagship videos. Recommended hybrid: keep YouTube + embed for most videos (free, keeps reach + ad money), self-host only the homepage/hero or top product videos.
- **Bunny Stream** — cheapest; free transcoding + free brandable player; ~$1/mo minimum, ~$0.01/GB storage, ~$0.005/GB delivery.
- **Cloudflare Stream** — $5 per 1,000 min stored + $1 per 1,000 min delivered (bandwidth included).
- **Plain MP4** (HTML5 video) — total control but no adaptive quality and gets expensive with traffic; only for a couple of short clips.
- Trade-off: self-hosting gives full branding + zero click-out + the SEO, but you pay for bandwidth and **lose** the YouTube view count, ad revenue, and discovery.

---

## 7. Quick reference: adding a video by hand

Until the generator exists, to add a video:
1. **Copy** an existing file in `videos/`, rename it to a short slug (e.g. `videos/new-trail-run.html`).
2. Inside it, replace the YouTube video ID everywhere, and update the title, description, date, and view count.
3. On the home page (`index.html`, in the "Latest Videos" grid), copy a card and update its `href` (the slug), the two thumbnail image URLs (the video ID), the title, and the date. There's a template in an HTML comment right above the cards.

_(This is fiddly because of the SEO data — the "Add a video" generator in section 6 would automate all of it.)_
