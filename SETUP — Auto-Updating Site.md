# Setting up the auto-updating website (one-time)

Once these steps are done, you never touch the website again — you just upload to YouTube and the site updates itself ~3× a day (with a manual "publish now" button for time-sensitive videos).

Everything is **free**. The only cost is owning the domain name (~$10–15/year), which you already have or will register.

There are 4 one-time parts. Take them one at a time — I can walk you through any of them live.

---

## Part 1 — Get a free YouTube data key (~5 min)

This lets the site read your channel's full video list and details.

1. Go to **https://console.cloud.google.com/** and sign in with your Google account.
2. At the top, click the project dropdown → **New Project** → name it `jensen-site` → **Create**. Wait a few seconds, then make sure it's selected.
3. In the search bar type **YouTube Data API v3**, open it, and click **Enable**.
4. Left menu → **APIs & Services → Credentials → + Create Credentials → API key**.
5. Copy the key it shows you (a long string). Keep it handy for Part 3.
6. (Recommended) Click the key → under **API restrictions**, choose **Restrict key → YouTube Data API v3 → Save**. This limits what the key can do.

> You do NOT need "OAuth" or a billing card. A plain API key is enough, and our usage is far under the free daily limit.

---

## Part 2 — Put the site on GitHub (~10 min)

1. Create a free account at **https://github.com/** (if you don't have one).
2. Click **+ (top right) → New repository**.
   - Name: `jensenoffroad` (or anything)
   - Visibility: **Public** ✅ (required for unlimited free automation)
   - Don't add a README. Click **Create repository**.
3. On the new repo page, click **uploading an existing file**.
4. Drag in **everything** from your `Jensen Off-Road` desktop folder — including the hidden `.github` folder. (If you don't see `.github`, in Windows File Explorer enable **View → Show → Hidden items** first.)
   - The important pieces: `index.html`, `styles.css`, `site.js`, `build.ps1`, `videos.json`, the `videos` folder, the two `logo` files, and the `.github` folder.
5. Click **Commit changes**.

---

## Part 3 — Add your key + turn on the robot (~3 min)

1. In your repo: **Settings → Secrets and variables → Actions → New repository secret**.
   - Name: `YT_API_KEY`
   - Secret: paste the key from Part 1 → **Add secret**.
2. **Settings → Pages**:
   - Under **Build and deployment → Source**, choose **GitHub Actions**.
3. Go to the **Actions** tab. If it asks to enable workflows, click **enable**. You'll see **"Build & deploy site."**
4. Click it → **Run workflow → Run workflow** (this is your manual "publish now" button).
5. Wait ~1–2 minutes for the green check. Your site is now live at the temporary address shown under **Settings → Pages** (something like `https://YOURNAME.github.io/jensenoffroad/`). Open it and confirm the videos show and play.

From now on it also runs automatically 3× a day. To publish a time-sensitive video immediately, just come back to **Actions → Build & deploy site → Run workflow**.

---

## Part 4 — Point your domain at it (~10 min + DNS wait)

1. In the repo: **Settings → Pages → Custom domain** → type `jensenoffroad.com` → **Save**.
2. Go to wherever you manage **jensenoffroad.com's DNS** (your domain registrar) and add:
   - Four **A records** for the apex (`@`) pointing to GitHub's IPs:
     `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
   - One **CNAME record**: name `www` → value `YOURNAME.github.io`
3. Back on **Settings → Pages**, once DNS propagates (minutes to a few hours), tick **Enforce HTTPS**.

> Tell me who your domain registrar is (GoDaddy, Namecheap, Cloudflare, etc.) and I'll give you the exact clicks for that specific one.

---

## That's it — how it works day to day

- **Upload to YouTube** from your phone, like always.
- Within a few hours the site adds a full SEO page for the new video, updates the home grid, and refreshes the sitemap — automatically.
- **Need it live right now?** Repo → **Actions → Build & deploy site → Run workflow**. Done in ~2 minutes.

## Previewing changes locally (optional)
Double-click **`Preview Site.bat`** to see the current site in your browser before/without publishing.

## To re-run the generator on your own PC (optional)
Open PowerShell in the folder and run:
```powershell
$env:YT_API_KEY = "your-key-here"
.\build.ps1
```
Leave the key off (or run `.\build.ps1 -NoFetch`) to just rebuild the pages from the saved catalog without contacting YouTube.

## Good to know
- **Search Console:** after the domain is live, add the site to **Google Search Console** and submit `https://jensenoffroad.com/sitemap.xml` so Google indexes your video pages faster. (I can walk you through this.)
- The repo being **public** only means your site's *code* is visible (it would be downloadable from any website anyway). Nothing private is exposed; your API key is stored as an encrypted secret, not in the code.
- GitHub pauses the daily schedule if the repo has zero activity for 60 days — but since the robot commits updates regularly, that won't happen in normal use.
