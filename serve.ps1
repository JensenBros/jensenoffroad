# Jensen Off-Road - local preview server.
# Serves this folder over http://localhost so YouTube players work locally
# (they cannot run from a double-clicked file:// page). Close the window to stop.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$mt = @{
  '.html'='text/html; charset=utf-8'; '.css'='text/css'; '.js'='application/javascript';
  '.svg'='image/svg+xml'; '.json'='application/json'; '.png'='image/png';
  '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.gif'='image/gif'; '.webp'='image/webp';
  '.ico'='image/x-icon'; '.mp4'='video/mp4'; '.webm'='video/webm'; '.txt'='text/plain'
}

# Find a free port from a short list.
$listener = $null
$port = $null
foreach ($p in 8080, 8081, 8090, 8123, 8765) {
  try {
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://localhost:$p/")
    $l.Start()
    $listener = $l; $port = $p; break
  } catch { if ($l) { $l.Close() } }
}
if (-not $listener) {
  Write-Host "Could not open a local port (8080/8081/8090/8123/8765 all busy)." -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}

Write-Host ""
Write-Host "  Jensen Off-Road - local preview" -ForegroundColor Green
Write-Host "  Serving: $root"
Write-Host "  Address: http://localhost:$port/"
Write-Host "  Videos will play on the page here, just like the live site."
Write-Host ""
Write-Host "  Keep this window open while previewing. Close it to stop." -ForegroundColor Yellow
Write-Host ""
Start-Process "http://localhost:$port/"

while ($listener.IsListening) {
  try {
    $ctx = $listener.GetContext()
    $rel = [System.Uri]::UnescapeDataString($ctx.Request.Url.LocalPath).TrimStart('/')
    if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }
    $full = Join-Path $root $rel
    if (Test-Path $full -PathType Leaf) {
      $bytes = [System.IO.File]::ReadAllBytes($full)
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      if ($mt.ContainsKey($ext)) { $ctx.Response.ContentType = $mt[$ext] } else { $ctx.Response.ContentType = 'application/octet-stream' }
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $ctx.Response.StatusCode = 404
      $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $rel")
      $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
    }
    $ctx.Response.Close()
  } catch { }
}
