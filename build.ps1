<#
  Jensen Off-Road - site generator.

  WHAT IT DOES
    1. (If a YouTube API key is present) fetches the channel's uploads and merges
       them into videos.json by video ID - older videos are never lost, slugs are
       never changed, private/deleted videos are dropped.
    2. Regenerates every videos/<slug>.html page (with VideoObject SEO data),
       the home-page video grid, and sitemap.xml from videos.json.

  HOW IT RUNS
    - Locally:  set $env:YT_API_KEY then run  .\build.ps1   (or  .\build.ps1 -NoFetch
      to only re-render from the existing videos.json without calling YouTube).
    - In CI:    GitHub Actions runs  .\build.ps1  with YT_API_KEY from repo secrets.

  Targets Windows PowerShell 5.1 (matches the GitHub Actions windows runner).
#>
param([switch]$NoFetch)

$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$root      = $PSScriptRoot
$dataPath  = Join-Path $root 'videos.json'
$indexPath = Join-Path $root 'index.html'
$videosDir = Join-Path $root 'videos'
$siteUrl   = 'https://jensenoffroad.com'   # used for canonical URLs + sitemap
$maxHome   = 24                            # max cards shown on the home grid
$enc       = New-Object System.Text.UTF8Encoding($false)
$inv       = [System.Globalization.CultureInfo]::InvariantCulture

# ---------- helpers ----------
function Write-Utf8($path, $text) { [System.IO.File]::WriteAllText($path, $text, $enc) }

function HtmlEnc([string]$s) { (($s -replace '&', '&amp;') -replace '<', '&lt;') -replace '>', '&gt;' -replace '"', '&quot;' }

function Clean-Text([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return '' }
  $t = $s
  $t = [regex]::Replace($t, 'https?://\S+', '')                                  # URLs
  $t = [regex]::Replace($t, '@[A-Za-z0-9_.]+', '')                              # @mentions
  $t = [regex]::Replace($t, '#[A-Za-z0-9_]+', '')                              # #hashtags
  foreach ($cp in 0xFFFC, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2060, 0xFEFF) { $t = $t.Replace([string][char]$cp, '') }  # object-replacement + zero-width chars (ASCII source so it survives the code page)
  $t = [regex]::Replace($t, '[ \t]{2,}', ' ')                                   # collapse runs of spaces
  $t = [regex]::Replace($t, '[ \t]+(\r?\n)', '$1')                              # trailing spaces per line
  $t = [regex]::Replace($t, '(\r?\n){3,}', "`n`n")                              # 3+ blank lines -> 1
  return $t.Trim()
}

function Clean-Title([string]$s) { ([regex]::Replace((Clean-Text $s), '\s+', ' ')).Trim() }

function New-Slug([string]$cleanTitle, [hashtable]$used) {
  $s = $cleanTitle.ToLowerInvariant()
  $s = [regex]::Replace($s, '[^a-z0-9]+', '-')
  $s = $s.Trim('-')
  if ($s.Length -gt 60) { $s = $s.Substring(0, 60).Trim('-') }
  if ([string]::IsNullOrEmpty($s)) { $s = 'video' }
  $base = $s; $i = 2
  while ($used.ContainsKey($s)) { $s = "$base-$i"; $i++ }
  $used[$s] = $true
  return $s
}

function Date-Fmt([string]$iso, [string]$fmt) {
  try { return ([datetimeoffset]::Parse($iso)).UtcDateTime.ToString($fmt, $inv) } catch { return '' }
}
function Views-Fmt($n) { try { return ([int64]$n).ToString('N0', $inv) } catch { return "$n" } }

# Best available thumbnail URL from a YouTube snippet.thumbnails object.
# maxresdefault.jpg is NOT guaranteed (esp. for Shorts), so prefer what the API actually has;
# fall back to hqdefault.jpg, which always exists.
function Best-Thumb($thumbs, $id) {
  if ($thumbs) {
    foreach ($k in 'maxres', 'standard', 'high', 'medium', 'default') {
      if ($thumbs.$k -and $thumbs.$k.url) { return [string]$thumbs.$k.url }
    }
  }
  return "https://i.ytimg.com/vi/$id/hqdefault.jpg"
}

# Set or add a NoteProperty (entries from older runs won't have the new fields yet).
function Set-Prop($obj, [string]$name, $value) { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }

# Readable label from a Wikipedia topic URL, e.g. ".../wiki/Off-roading" -> "Off-roading".
function Topic-Name([string]$url) {
  $seg = ($url -split '/wiki/')[-1]
  try { $seg = [System.Uri]::UnescapeDataString($seg) } catch { }
  ($seg -replace '_', ' ').Trim()
}

# Coerce a possibly-null API list into a real array (avoid @(null) -> 1-element array).
function As-Array($x) { if ($null -eq $x) { return , @() } else { return , @($x) } }   # comma-wrap so a single-element list isn't unwrapped to a scalar on return

# ---------- load catalog ----------
if (-not (Test-Path $dataPath)) { throw "videos.json not found at $dataPath" }
$data = [System.IO.File]::ReadAllText($dataPath) | ConvertFrom-Json
if (-not $data.videos) { $data | Add-Member -NotePropertyName videos -NotePropertyValue @() -Force }

# ---------- fetch from YouTube (optional) ----------
$apiKey = $env:YT_API_KEY
if (-not $NoFetch -and $apiKey) {
  try {
    $cid = $data.channelId
    # 1) uploads playlist id
    $uploads = $null
    try {
      $ch = Invoke-RestMethod -TimeoutSec 30 -Uri "https://www.googleapis.com/youtube/v3/channels?part=contentDetails&id=$cid&key=$apiKey"
      $uploads = $ch.items[0].contentDetails.relatedPlaylists.uploads
    } catch { }
    if (-not $uploads) { $uploads = 'UU' + $cid.Substring(2) }   # UC->UU fallback

    # 2) all upload items (paginated)
    $items = @{}
    $token = $null
    do {
      $u = "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet,contentDetails&maxResults=50&playlistId=$uploads&key=$apiKey"
      if ($token) { $u += "&pageToken=$token" }
      $resp = Invoke-RestMethod -TimeoutSec 30 -Uri $u
      foreach ($it in $resp.items) {
        $vid = $it.snippet.resourceId.videoId
        if ($vid) { $items[$vid] = $it }
      }
      $token = $resp.nextPageToken
    } while ($token)

    # 3) full details (batches of 50): snippet (full description, tags, category),
    #    contentDetails (duration), statistics (views/likes/comments),
    #    topicDetails (topic categories), recordingDetails (recording date)
    $details = @{}
    $ids = @($items.Keys)
    for ($i = 0; $i -lt $ids.Count; $i += 50) {
      $hi = [math]::Min($i + 49, $ids.Count - 1)
      $batch = ($ids[$i..$hi]) -join ','
      $vr = Invoke-RestMethod -TimeoutSec 30 -Uri "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails,statistics,topicDetails,recordingDetails&id=$batch&key=$apiKey"
      foreach ($v in $vr.items) { $details[$v.id] = $v }
    }

    # 3b) one-time category id -> name map (cached for the run)
    $catMap = @{}
    try {
      $cr = Invoke-RestMethod -TimeoutSec 30 -Uri "https://www.googleapis.com/youtube/v3/videoCategories?part=snippet&regionCode=US&key=$apiKey"
      foreach ($c in $cr.items) { $catMap[[string]$c.id] = [string]$c.snippet.title }
    } catch { Write-Warning "videoCategories.list failed; category names will be blank." }

    # 4) merge into the catalog (preserve slugs; never drop a known video on a partial pull)
    $existing = @{}
    foreach ($v in $data.videos) { $existing[$v.id] = $v }
    $used = @{}
    foreach ($v in $data.videos) { if ($v.slug) { $used[$v.slug] = $true } }

    $newList = New-Object System.Collections.ArrayList
    foreach ($vid in $items.Keys) {
      $it = $items[$vid]
      $det = $details[$vid]
      $existingEntry = $existing[$vid]
      if ($null -eq $det) {
        # videos.list returned no details for this id (private placeholder, OR a partial
        # API response). Never delete a video we already know about: carry it forward
        # unchanged. Only skip when there is nothing to preserve.
        if ($existingEntry) { [void]$newList.Add($existingEntry) }
        continue
      }
      $pub = $it.contentDetails.videoPublishedAt
      if (-not $pub) { $pub = $it.snippet.publishedAt }
      $sn = $det.snippet      # full snippet from videos.list (full description, tags, category)
      $st = if ($det.statistics) { $det.statistics } else { [pscustomobject]@{} }   # stats can be hidden on some videos; never let one null crash the whole merge

      # New entry gets a slug once (never changed); existing entry is reused.
      if ($null -eq $existingEntry) {
        $entry = [pscustomobject]@{ id = $vid; slug = (New-Slug (Clean-Title ([string]$sn.title)) $used) }
      } else {
        $entry = $existingEntry
      }

      Set-Prop $entry 'title'           ([string]$sn.title)
      Set-Prop $entry 'description'     ([string]$sn.description)          # full description (videos.list, not the truncated playlist one)
      Set-Prop $entry 'publishedAt'     ([string]$pub)
      Set-Prop $entry 'duration'        ([string]$det.contentDetails.duration)
      Set-Prop $entry 'viewCount'       ([int64]$st.viewCount)
      Set-Prop $entry 'thumbnail'       (Best-Thumb $it.snippet.thumbnails $vid)
      Set-Prop $entry 'tags'            (As-Array $sn.tags)
      Set-Prop $entry 'categoryName'    $(if ($sn.categoryId -and $catMap.ContainsKey([string]$sn.categoryId)) { $catMap[[string]$sn.categoryId] } else { '' })
      Set-Prop $entry 'topicCategories' (As-Array $det.topicDetails.topicCategories)
      Set-Prop $entry 'likeCount'       $(if ($st.PSObject.Properties['likeCount']) { [int64]$st.likeCount } else { $null })
      Set-Prop $entry 'commentCount'    $(if ($st.PSObject.Properties['commentCount']) { [int64]$st.commentCount } else { $null })
      Set-Prop $entry 'recordingDate'   $(if ($det.recordingDetails -and $det.recordingDetails.recordingDate) { [string]$det.recordingDetails.recordingDate } else { '' })
      [void]$newList.Add($entry)
    }
    # Completeness guard: only accept the fetched catalog if it isn't suspiciously
    # smaller than what we already have (protects against a throttled/partial pull
    # silently deleting published pages, which the orphan sweep would then remove).
    $minKeep = [math]::Floor($data.videos.Count * 0.9)
    if ($newList.Count -gt 0 -and $newList.Count -ge $minKeep) {
      $data.videos = $newList.ToArray()
      Write-Host "Merged $($newList.Count) videos from YouTube."
    } else {
      Write-Warning "Fetch returned $($newList.Count) vs existing $($data.videos.Count) - suspected partial pull; keeping existing catalog."
    }
  } catch {
    Write-Warning "YouTube fetch failed ($($_.Exception.Message)). Rendering from existing videos.json."
  }
} elseif (-not $NoFetch) {
  Write-Host "No YT_API_KEY set - rendering from existing videos.json (run with a key to pull new videos)."
}

# ---------- normalize + sort ----------
$used = @{}
foreach ($v in $data.videos) { if ($v.slug) { $used[$v.slug] = $true } }
foreach ($v in $data.videos) {
  if (-not $v.slug) { $v | Add-Member -NotePropertyName slug -NotePropertyValue (New-Slug (Clean-Title $v.title) $used) -Force }
}
$sorted = @($data.videos | Sort-Object {
    $dt = [datetimeoffset]::MinValue
    [void][datetimeoffset]::TryParse($_.publishedAt, [ref]$dt)
    $dt
  } -Descending)

# Precompute a tag+topic key-set per video so "related" can be topical (fast O(1) lookups).
$keySets = @{}
foreach ($v in $sorted) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($t in (As-Array $v.tags)) { if ($t) { [void]$set.Add(([string]$t).ToLowerInvariant()) } }
  foreach ($t in (As-Array $v.topicCategories)) { if ($t) { [void]$set.Add(([string]$t).ToLowerInvariant()) } }
  $keySets[$v.id] = $set
}

# ---------- renderers ----------
function Render-Card($v, [string]$prefix) {
  $t = HtmlEnc (Clean-Title $v.title)
  $d = Date-Fmt $v.publishedAt 'MMM d, yyyy'
  $id = $v.id; $href = "$prefix$($v.slug).html"
@"
        <a class="video-card" href="$href">
          <div class="thumb">
            <img class="poster" loading="lazy" alt="" src="https://i.ytimg.com/vi/$id/maxresdefault.jpg"
                 onerror="this.onerror=null;this.src='https://i.ytimg.com/vi/$id/hqdefault.jpg';" />
            <span class="play"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg></span>
          </div>
          <div class="video-meta">
            <h3>$t</h3>
            <p>$d</p>
          </div>
        </a>
"@
}

function Render-VideoPage($v, $all) {
  $id = $v.id; $slug = $v.slug
  $cleanTitle = Clean-Title $v.title
  $titleEnc = HtmlEnc $cleanTitle
  $descClean = Clean-Text $v.description
  if ([string]::IsNullOrWhiteSpace($descClean)) { $descClean = "$cleanTitle - off-road video from Jensen Off-Road." }
  $descEnc = HtmlEnc $descClean
  $metaSrc = ($descClean -replace '\s+', ' ').Trim()
  if ($metaSrc.Length -gt 160) { $metaSrc = $metaSrc.Substring(0, 157).TrimEnd() + '...' }
  $metaEnc = HtmlEnc $metaSrc
  $datePretty = Date-Fmt $v.publishedAt 'MMMM d, yyyy'
  $viewsPretty = Views-Fmt $v.viewCount
  $channelId = $data.channelId
  $hqUrl = "https://i.ytimg.com/vi/$id/hqdefault.jpg"
  $ogImage = if ($v.PSObject.Properties['thumbnail'] -and $v.thumbnail) { [string]$v.thumbnail } else { $hqUrl }
  $thumbList = @($ogImage); if ($ogImage -ne $hqUrl) { $thumbList += $hqUrl }

  # ----- enrichment fields (all optional / guarded) -----
  $tags = As-Array $v.tags
  $shownTags = @($tags | Select-Object -First 12)   # cap the visible + keyword set so it isn't a keyword-stuffed wall
  $topics = As-Array $v.topicCategories
  $catName = if ($v.PSObject.Properties['categoryName']) { [string]$v.categoryName } else { '' }
  $likeCount = $null;    if ($v.likeCount)    { try { $likeCount    = [int64]$v.likeCount }    catch {} }
  $commentCount = $null; if ($v.commentCount) { try { $commentCount = [int64]$v.commentCount } catch {} }
  $recPretty = ''
  if ($v.PSObject.Properties['recordingDate'] -and $v.recordingDate) {
    $rd = Date-Fmt ([string]$v.recordingDate) 'MMMM d, yyyy'
    if ($rd -and $rd -ne 'January 1, 1970') { $recPretty = $rd }
  }

  # visible stats line (date / views / likes / comments / filmed-on)
  $statBits = @("<span>$datePretty</span>", "<span>$viewsPretty views</span>")
  if ($likeCount)    { $statBits += '<span>' + (Views-Fmt $likeCount)    + ' likes</span>' }
  if ($commentCount) { $statBits += '<span>' + (Views-Fmt $commentCount) + ' comments</span>' }
  if ($recPretty)    { $statBits += '<span>Filmed ' + (HtmlEnc $recPretty) + '</span>' }
  $statsHtml = ($statBits -join '<span class="dot">&bull;</span>')

  # category + topic entity links (visible)
  $topoParts = @()
  if ($catName) { $topoParts += '<span class="topic-cat">' + (HtmlEnc $catName) + '</span>' }
  foreach ($u in $topics) {
    $tn = Topic-Name ([string]$u)
    if ($tn) { $topoParts += '<span class="topic">' + (HtmlEnc $tn) + '</span>' }   # plain label, no outbound link (keeps visitors on-site)
  }
  $topicsHtml = ''
  if ($topoParts.Count -gt 0) { $topicsHtml = '<div class="topics"><span class="topics-label">Topics:</span> ' + ($topoParts -join ' ') + '</div>' }

  # multi-paragraph description (split on blank lines; single newlines become <br />)
  $descHtml = (($descClean -split '(?:\r?\n){2,}' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { '<p>' + ((HtmlEnc $_.Trim()) -replace '\r?\n', '<br />') + '</p>' }) -join "`n        ")
  if (-not $descHtml) { $descHtml = "<p>$descEnc</p>" }

  # tag chips (visible)
  $tagsHtml = ''
  if ($shownTags.Count -gt 0) {
    $chips = (($shownTags | ForEach-Object { '<span class="tag">' + (HtmlEnc ([string]$_)) + '</span>' }) -join ' ')
    $tagsHtml = '<div class="tags" aria-label="Tags">' + $chips + '</div>'
  }

  # ----- VideoObject JSON-LD (mirrors the visible content above) -----
  $ld = [ordered]@{
    '@context' = 'https://schema.org'; '@type' = 'VideoObject'
    name = $cleanTitle; description = $descClean
    thumbnailUrl = $thumbList
    uploadDate = $v.publishedAt
  }
  if ($v.duration) { $ld['duration'] = $v.duration }
  $ld['embedUrl'] = "https://www.youtube.com/embed/$id"
  $ld['contentUrl'] = "https://www.youtube.com/watch?v=$id"
  if ($shownTags.Count -gt 0) { $ld['keywords'] = ($shownTags -join ', ') }
  if ($catName) { $ld['genre'] = $catName }
  if ($topics.Count -gt 0) {
    $ld['about'] = @($topics | ForEach-Object { [ordered]@{ '@type' = 'Thing'; name = (Topic-Name ([string]$_)); sameAs = [string]$_ } })
  }
  $interactions = @([ordered]@{ '@type' = 'InteractionCounter'; interactionType = [ordered]@{ '@type' = 'https://schema.org/WatchAction' }; userInteractionCount = [int64]$v.viewCount })
  if ($likeCount)    { $interactions += [ordered]@{ '@type' = 'InteractionCounter'; interactionType = [ordered]@{ '@type' = 'https://schema.org/LikeAction' };    userInteractionCount = $likeCount } }
  if ($commentCount) { $interactions += [ordered]@{ '@type' = 'InteractionCounter'; interactionType = [ordered]@{ '@type' = 'https://schema.org/CommentAction' }; userInteractionCount = $commentCount } }
  $ld['interactionStatistic'] = $interactions
  $ld['publisher'] = [ordered]@{ '@type' = 'Organization'; name = 'Jensen Off-Road'; logo = [ordered]@{ '@type' = 'ImageObject'; url = "$siteUrl/logo.svg" } }
  $jsonld = ($ld | ConvertTo-Json -Depth 8) -replace ([char]0x3c), ([char]0x5c + 'u003c')

  # ----- BreadcrumbList JSON-LD (matches the visible breadcrumb) -----
  $crumb = [ordered]@{
    '@context' = 'https://schema.org'; '@type' = 'BreadcrumbList'
    itemListElement = @(
      [ordered]@{ '@type' = 'ListItem'; position = 1; name = 'Home'; item = "$siteUrl/" }
      [ordered]@{ '@type' = 'ListItem'; position = 2; name = 'Videos'; item = "$siteUrl/all-videos.html" }
      [ordered]@{ '@type' = 'ListItem'; position = 3; name = $cleanTitle; item = "$siteUrl/videos/$slug.html" }
    )
  }
  $crumbJson = ($crumb | ConvertTo-Json -Depth 6) -replace ([char]0x3c), ([char]0x5c + 'u003c')

  # ----- topical related (shared tags/topics, fall back to recency) -----
  $mySet = $keySets[$id]
  $ix = 0
  $scored = foreach ($c in $all) {
    if ($c.id -ne $id) {
      $cs = $keySets[$c.id]; $score = 0
      if ($mySet -and $cs -and $mySet.Count -gt 0 -and $cs.Count -gt 0) {
        foreach ($k in $mySet) { if ($cs.Contains($k)) { $score++ } }
      }
      [pscustomobject]@{ v = $c; score = $score; idx = $ix }
      $ix++
    }
  }
  $others = @($scored | Sort-Object @{Expression = 'score'; Descending = $true }, @{Expression = 'idx'; Descending = $false } | Select-Object -First 3 | ForEach-Object { $_.v })
  $relatedHtml = (($others | ForEach-Object { Render-Card $_ '' }) -join "`n")

@"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>$titleEnc | Jensen Off-Road</title>
  <meta name="description" content="$metaEnc" />
  <link rel="canonical" href="$siteUrl/videos/$slug.html" />

  <!-- Open Graph -->
  <meta property="og:type" content="video.other" />
  <meta property="og:site_name" content="Jensen Off-Road" />
  <meta property="og:title" content="$titleEnc" />
  <meta property="og:description" content="$metaEnc" />
  <meta property="og:url" content="$siteUrl/videos/$slug.html" />
  <meta property="og:image" content="$ogImage" />
  <meta property="og:video" content="https://www.youtube.com/embed/$id" />
  <meta property="og:video:type" content="text/html" />
  <meta property="og:video:width" content="1280" />
  <meta property="og:video:height" content="720" />

  <!-- Twitter -->
  <meta name="twitter:card" content="player" />
  <meta name="twitter:title" content="$titleEnc" />
  <meta name="twitter:description" content="$metaEnc" />
  <meta name="twitter:image" content="$ogImage" />
  <meta name="twitter:player" content="https://www.youtube.com/embed/$id" />
  <meta name="twitter:player:width" content="1280" />
  <meta name="twitter:player:height" content="720" />

  <link rel="stylesheet" href="../styles.css" />

  <script type="application/ld+json">
$jsonld
  </script>
  <script type="application/ld+json">
$crumbJson
  </script>
</head>
<body>

  <!-- ===== Header ===== -->
  <header>
    <div class="wrap nav">
      <a href="../index.html" class="brand" aria-label="Jensen Off-Road home">
        <img src="../logo-light.svg" alt="Jensen Bros. Off-Road" class="logo" />
      </a>
      <nav class="nav-links" id="navLinks">
        <a href="../index.html#videos">Videos</a>
        <a href="../index.html#about">About</a>
        <a href="../index.html#contact">Contact</a>
      </nav>
      <button class="menu-btn" id="menuBtn" aria-label="Toggle menu">&#9776;</button>
    </div>
  </header>

  <main class="wrap video-page">
    <div class="video-main">
      <nav class="breadcrumb" aria-label="Breadcrumb">
        <a href="../index.html">Home</a> / <a href="../index.html#videos">Videos</a> / <span>$titleEnc</span>
      </nav>

      <div class="player">
        <iframe id="player-frame" data-ytid="$id"
                src="https://www.youtube-nocookie.com/embed/${id}?rel=0&amp;playsinline=1&amp;iv_load_policy=3&amp;cc_load_policy=0"
                title="$titleEnc"
                allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share"
                allowfullscreen loading="lazy"></iframe>
      </div>

      <h1>$titleEnc</h1>
      <div class="video-stats">$statsHtml</div>
      $topicsHtml

      <div class="video-actions">
        <a class="btn btn-primary" href="../index.html#videos">More Jensen videos</a>
        <a class="sub-link" href="https://www.youtube.com/channel/${channelId}?sub_confirmation=1" target="_blank" rel="noopener">Subscribe on YouTube &#8599;</a>
      </div>

      <div class="video-desc">
        <h2>About this video</h2>
        $descHtml
        $tagsHtml
      </div>
    </div>

    <!-- ===== Related ===== -->
    <section class="related">
      <h2>More from Jensen Off-Road</h2>
      <div class="video-grid">
$relatedHtml
      </div>
    </section>
  </main>

  <!-- ===== Footer ===== -->
  <footer>
    <div class="wrap foot">
      <div>
        <div class="brand" style="margin-bottom:14px;">
          <img src="../logo-light.svg" alt="Jensen Bros. Off-Road" class="logo" />
        </div>
        <div class="copyright">&copy; <span id="year"></span> Jensen Off-Road. All rights reserved.</div>
      </div>
      <div class="socials">
        <a href="https://www.youtube.com/channel/$channelId" target="_blank" rel="noopener" aria-label="YouTube" title="YouTube">
          <svg viewBox="0 0 24 24" fill="currentColor"><path d="M23 12s0-3.8-.5-5.6a2.9 2.9 0 0 0-2-2C18.7 4 12 4 12 4s-6.7 0-8.5.4a2.9 2.9 0 0 0-2 2C1 8.2 1 12 1 12s0 3.8.5 5.6a2.9 2.9 0 0 0 2 2C5.3 20 12 20 12 20s6.7 0 8.5-.4a2.9 2.9 0 0 0 2-2C23 15.8 23 12 23 12zM10 15.5v-7l6 3.5z"/></svg>
        </a>
      </div>
    </div>
  </footer>

  <script src="../site.js"></script>
</body>
</html>
"@
}

# ---------- write video pages ----------
if (-not (Test-Path $videosDir)) { New-Item -ItemType Directory -Path $videosDir | Out-Null }
$wantFiles = @{}
foreach ($v in $sorted) {
  $file = Join-Path $videosDir ($v.slug + '.html')
  Write-Utf8 $file (Render-VideoPage $v $sorted)
  $wantFiles[($v.slug + '.html')] = $true
}
# remove orphaned pages (videos no longer in catalog)
Get-ChildItem -Path $videosDir -Filter *.html | ForEach-Object {
  if (-not $wantFiles.ContainsKey($_.Name)) { Remove-Item $_.FullName -Force; Write-Host "Removed orphan page $($_.Name)" }
}

# ---------- home grid ----------
$cards = (($sorted | Select-Object -First $maxHome | ForEach-Object { Render-Card $_ 'videos/' }) -join "`n`n")
$index = [System.IO.File]::ReadAllText($indexPath)
$gridEval = [System.Text.RegularExpressions.MatchEvaluator] {
  param($m) $m.Groups[1].Value + "`n" + $cards + "`n        " + $m.Groups[2].Value
}
$index = [System.Text.RegularExpressions.Regex]::Replace($index, '(?s)(<!-- VIDEOS:START -->).*?(<!-- VIDEOS:END -->)', $gridEval)
Write-Utf8 $indexPath $index

# ---------- all-videos hub page (every video linked server-side, grouped by year) ----------
$hubRows = New-Object System.Text.StringBuilder
$curYear = ''
foreach ($v in $sorted) {
  $y = Date-Fmt $v.publishedAt 'yyyy'
  if (-not $y) { $y = 'Other' }
  if ($y -ne $curYear) {
    if ($curYear -ne '') { [void]$hubRows.AppendLine('      </ul>') }
    [void]$hubRows.AppendLine("      <h2 class=`"year`">$y</h2>")
    [void]$hubRows.AppendLine('      <ul class="all-videos">')
    $curYear = $y
  }
  $t = HtmlEnc (Clean-Title $v.title)
  $d = Date-Fmt $v.publishedAt 'MMM d, yyyy'
  [void]$hubRows.AppendLine("        <li><a href=`"videos/$($v.slug).html`">$t</a> <span class=`"date`">$d</span></li>")
}
if ($curYear -ne '') { [void]$hubRows.AppendLine('      </ul>') }

$hubHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>All Videos | Jensen Off-Road</title>
  <meta name="description" content="Every Jensen Off-Road video - off-road builds, Moab rock-crawling, Ultra4 racing, and GEN-3 ORI strut footage." />
  <link rel="canonical" href="$siteUrl/all-videos.html" />
  <meta property="og:type" content="website" />
  <meta property="og:title" content="All Videos | Jensen Off-Road" />
  <meta property="og:url" content="$siteUrl/all-videos.html" />
  <link rel="stylesheet" href="styles.css" />
</head>
<body>
  <header>
    <div class="wrap nav">
      <a href="index.html" class="brand" aria-label="Jensen Off-Road home">
        <img src="logo-light.svg" alt="Jensen Bros. Off-Road" class="logo" />
      </a>
      <nav class="nav-links" id="navLinks">
        <a href="index.html#videos">Videos</a>
        <a href="all-videos.html">All Videos</a>
        <a href="index.html#about">About</a>
      </nav>
      <button class="menu-btn" id="menuBtn" aria-label="Toggle menu">&#9776;</button>
    </div>
  </header>

  <main class="wrap video-page">
    <div class="video-main">
      <nav class="breadcrumb" aria-label="Breadcrumb">
        <a href="index.html">Home</a> / <span>All Videos</span>
      </nav>
      <h1>All Videos</h1>
      <p class="all-intro">Every video from Jensen Off-Road - $($sorted.Count) and counting.</p>
$($hubRows.ToString())
    </div>
  </main>

  <footer>
    <div class="wrap foot">
      <div>
        <div class="brand" style="margin-bottom:14px;">
          <img src="logo-light.svg" alt="Jensen Bros. Off-Road" class="logo" />
        </div>
        <div class="copyright">&copy; <span id="year"></span> Jensen Off-Road. All rights reserved.</div>
      </div>
      <div class="socials">
        <a href="https://www.youtube.com/channel/$($data.channelId)" target="_blank" rel="noopener" aria-label="YouTube" title="YouTube">
          <svg viewBox="0 0 24 24" fill="currentColor"><path d="M23 12s0-3.8-.5-5.6a2.9 2.9 0 0 0-2-2C18.7 4 12 4 12 4s-6.7 0-8.5.4a2.9 2.9 0 0 0-2 2C1 8.2 1 12 1 12s0 3.8.5 5.6a2.9 2.9 0 0 0 2 2C5.3 20 12 20 12 20s6.7 0 8.5-.4a2.9 2.9 0 0 0 2-2C23 15.8 23 12 23 12zM10 15.5v-7l6 3.5z"/></svg>
        </a>
      </div>
    </div>
  </footer>

  <script src="site.js"></script>
</body>
</html>
"@
Write-Utf8 (Join-Path $root 'all-videos.html') $hubHtml

# ---------- sitemap ----------
$today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
[void]$sb.AppendLine("  <url><loc>$siteUrl/</loc><lastmod>$today</lastmod></url>")
[void]$sb.AppendLine("  <url><loc>$siteUrl/all-videos.html</loc><lastmod>$today</lastmod></url>")
foreach ($v in $sorted) {
  $lm = Date-Fmt $v.publishedAt 'yyyy-MM-dd'
  if (-not $lm) { $lm = $today }
  [void]$sb.AppendLine("  <url><loc>$siteUrl/videos/$($v.slug).html</loc><lastmod>$lm</lastmod></url>")
}
[void]$sb.AppendLine('</urlset>')
Write-Utf8 (Join-Path $root 'sitemap.xml') ($sb.ToString())

# ---------- persist catalog ----------
$outData = [ordered]@{ channelId = $data.channelId; channelTitle = $data.channelTitle; videos = $sorted }
Write-Utf8 $dataPath (($outData | ConvertTo-Json -Depth 8))

Write-Host "Built $($sorted.Count) video pages, home grid, and sitemap.xml."
