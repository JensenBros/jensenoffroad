// Shared behavior for all Jensen Off-Road pages.

// Mobile menu toggle
var menuBtn = document.getElementById('menuBtn');
var navLinks = document.getElementById('navLinks');
if (menuBtn && navLinks) {
  menuBtn.addEventListener('click', function () {
    navLinks.classList.toggle('open');
  });
  navLinks.addEventListener('click', function (e) {
    if (e.target.tagName === 'A') navLinks.classList.remove('open');
  });
}

// Auto-update the copyright year
var yearEl = document.getElementById('year');
if (yearEl) yearEl.textContent = new Date().getFullYear();

// Video page: an embedded YouTube player can't run when the page is opened from a
// local file (file:// -> "Error 153"). In that case only, swap the player for a
// clickable thumbnail that opens the video on YouTube. Served over http(s) the
// inline player is left untouched and plays on-site.
var frame = document.getElementById('player-frame');
if (frame && location.protocol === 'file:') {
  var id = frame.getAttribute('data-ytid');
  var link = document.createElement('a');
  link.href = 'https://www.youtube.com/watch?v=' + id;
  link.target = '_blank';
  link.rel = 'noopener';
  link.className = 'player-fallback';
  link.setAttribute('aria-label', 'Watch on YouTube');
  link.innerHTML =
    '<img src="https://i.ytimg.com/vi/' + id + '/maxresdefault.jpg" alt="" ' +
    'onerror="this.onerror=null;this.src=\'https://i.ytimg.com/vi/' + id + '/hqdefault.jpg\'">' +
    '<span class="play"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg></span>';
  frame.replaceWith(link);
}
