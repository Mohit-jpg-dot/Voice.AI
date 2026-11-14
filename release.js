/**
 * Voice.AI Dynamic Release Manager
 * Reads latest.json, auto-detects OS (macOS vs Windows), binds download buttons, and renders honest release badges.
 */

(function () {
  'use strict';

  const FALLBACK_METADATA = {
    version: '1.1.0',
    buildNumber: '43',
    fileName: 'Voice.AI-1.1.0.dmg',
    fileSizeBytes: 16207681,
    sha256: 'b4605fe4cda2d2b2001588d9d1c4eb2f469e20ceecdf6811fb926563050b4509',
    downloadUrl: 'downloads/Voice.AI-1.1.0.dmg'
  };

  async function loadReleaseMetadata() {
    try {
      const response = await fetch('latest.json?t=' + Date.now());
      if (!response.ok) {
        throw new Error('Metadata fetch failed with status ' + response.status);
      }
      const data = await response.json();
      applyMetadata(data);
    } catch (err) {
      console.warn('Could not load dynamic release metadata, using local fallback:', err);
      applyMetadata(FALLBACK_METADATA);
    }
  }

  function formatBytes(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  }

  function applyMetadata(data) {
    const platform = (navigator.userAgentData?.platform || navigator.platform || navigator.userAgent || '').toLowerCase();
    const isWindows = platform.includes('win');
    const isMac = platform.includes('mac');
    const isDownloadPage = window.location.pathname.includes('download.html') || window.location.pathname.endsWith('/download');

    const downloadUrl = data.downloadUrl || 'downloads/Voice.AI-1.0.0.dmg';

    // 1. Update download buttons
    if (isDownloadPage) {
      document.querySelectorAll('.btn-mac-download-pill').forEach(btn => {
        btn.setAttribute('href', downloadUrl);
        btn.setAttribute('download', data.fileName || 'Voice.AI-1.0.0.dmg');
      });
      document.querySelectorAll('.btn-nav-download, #headerDownloadBtn').forEach(btn => {
        btn.setAttribute('href', downloadUrl);
        btn.setAttribute('download', data.fileName || 'Voice.AI-1.0.0.dmg');
      });
    } else {
      document.querySelectorAll('.btn-mac-download-pill, .btn-nav-download, #headerDownloadBtn').forEach(btn => {
        btn.setAttribute('href', 'download.html');
        btn.removeAttribute('download');
        if (isWindows) {
          btn.innerHTML = '<span class="btn-apple-logo">🪟</span> <span class="btn-text-main">Download for</span> <span class="btn-text-muted">Windows</span>';
        }
      });
    }

    // 2. Update metadata text elements if present
    document.querySelectorAll('.release-version-text').forEach(el => {
      el.textContent = `v${data.version} (Build ${data.buildNumber})`;
    });

    document.querySelectorAll('.release-size-text').forEach(el => {
      el.textContent = formatBytes(data.fileSizeBytes);
    });

    document.querySelectorAll('.release-sha-text').forEach(el => {
      el.textContent = data.sha256;
    });

    document.querySelectorAll('.release-date-text').forEach(el => {
      el.textContent = new Date(data.releaseDate).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric'
      });
    });

    // 3. Status Badge (Honest signing / notarization status)
    document.querySelectorAll('.release-status-badge').forEach(el => {
      if (data.signed && data.notarized) {
        el.className = 'release-status-badge status-verified';
        el.innerHTML = '✓ Signed & Notarized (Apple Developer ID)';
      } else {
        el.className = 'release-status-badge status-unsigned';
        el.innerHTML = '⚠️ Unsigned development build, not notarized';
      }
    });

    // 4. Platform Banner
    if (isWindows) {
      document.querySelectorAll('.platform-warning-pill').forEach(el => {
        el.style.display = 'inline-flex';
        el.innerHTML = '🪟 Windows detected! Download Voice.AI Preview for Windows 10 & 11 below.';
      });
    }
  }

  // Copy SHA-256 helper
  window.copyReleaseSha = function (btnElement) {
    const shaEl = document.querySelector('.release-sha-text');
    if (!shaEl) return;
    const hash = shaEl.textContent.trim();
    navigator.clipboard.writeText(hash).then(() => {
      const originalText = btnElement.innerText;
      btnElement.innerText = '✓ Copied!';
      setTimeout(() => {
        btnElement.innerText = originalText;
      }, 2000);
    });
  };

  document.addEventListener('DOMContentLoaded', loadReleaseMetadata);
})();
