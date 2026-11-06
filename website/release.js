/**
 * Voice.AI Dynamic Release Manager
 * Reads latest.json, binds download buttons to the verified DMG, and renders honest release badges.
 */

(function () {
  'use strict';

  const FALLBACK_METADATA = {
    version: '1.0.0',
    buildNumber: '42',
    fileName: 'Voice.AI-1.0.0.dmg',
    fileSizeBytes: 7348540,
    sha256: '720247d4f456461d0ea4f725718df27d6c5ee15bb4e7f69a172f2e7ade4b69dc',
    downloadUrl: 'downloads/Voice.AI-1.0.0.dmg'
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
    // 1. Update download buttons
    const downloadUrl = data.downloadUrl || 'downloads/Voice.AI-1.0.0.dmg';
    const isDownloadPage = window.location.pathname.includes('download.html') || window.location.pathname.endsWith('/download');

    if (isDownloadPage) {
      // On the dedicated download page: buttons initiate the direct DMG download
      document.querySelectorAll('.btn-mac-download-pill, .btn-nav-download, #headerDownloadBtn').forEach(btn => {
        btn.setAttribute('href', downloadUrl);
        btn.setAttribute('download', data.fileName || 'Voice.AI-1.0.0.dmg');
      });
    } else {
      // On all other pages (index, about, blog, app-store):
      // All download buttons redirect the user directly to download.html!
      document.querySelectorAll('.btn-mac-download-pill, .btn-nav-download, #headerDownloadBtn').forEach(btn => {
        btn.setAttribute('href', 'download.html');
        btn.removeAttribute('download');
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

    // 4. Non-Mac OS Detection
    const platform = (navigator.userAgentData?.platform || navigator.platform || navigator.userAgent || '').toLowerCase();
    const isMac = platform.includes('mac');
    if (!isMac) {
      document.querySelectorAll('.platform-warning-pill').forEach(el => {
        el.style.display = 'inline-flex';
        el.textContent = 'Voice.AI is built natively for macOS. Windows version in preview.';
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

