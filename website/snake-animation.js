/**
 * Voice.AI Running Snake App Icons Animation
 * Renders real app icons that travel along an S-curved ribbon behind the Voice.AI card.
 * Matches design reference in media_1793869046159_155363fb.jpg
 */

(function () {
  'use strict';

  const APP_ICONS = [
    {
      name: "Telegram",
      bg: "#24A1DE",
      svg: `<svg viewBox="0 0 24 24" width="28" height="28" fill="#ffffff">
              <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm4.64 6.8c-.15 1.58-.8 5.42-1.13 7.19-.14.75-.42 1-.68 1.03-.58.05-1.02-.38-1.58-.75-.88-.58-1.38-.94-2.23-1.5-.99-.65-.35-1.01.22-1.59.15-.15 2.71-2.48 2.76-2.69a.2.2 0 00-.05-.18c-.06-.05-.14-.03-.21-.02-.09.02-1.49.95-4.22 2.79-.4.27-.76.41-1.08.4-.36-.01-1.04-.2-1.55-.37-.63-.2-1.12-.31-1.08-.66.02-.18.27-.36.75-.55 2.92-1.27 4.86-2.11 5.83-2.51 2.78-1.16 3.35-1.36 3.73-1.36.08 0 .27.02.39.12.1.08.13.19.14.27-.01.06.01.24 0 .37z"/>
            </svg>`
    },
    {
      name: "Apple Calendar",
      bg: "#ffffff",
      svg: `<div style="display:flex; flex-direction:column; align-items:center; width:100%; height:100%; justify-content:center; padding: 2px 0;">
              <span style="font-size:9px; font-weight:800; color:#ff3b30; text-transform:uppercase; line-height:1; letter-spacing:0.5px;">Tue</span>
              <span style="font-size:20px; font-weight:800; color:#1c1c1e; line-height:1.1;">1</span>
            </div>`
    },
    {
      name: "Shortcuts",
      bg: "#1C1C1E",
      svg: `<svg viewBox="0 0 24 24" width="28" height="28">
              <rect x="3" y="7" width="12" height="12" rx="4" fill="#FF2D55" transform="rotate(-25 9 13)"/>
              <rect x="9" y="5" width="12" height="12" rx="4" fill="#5856D6" opacity="0.9" transform="rotate(25 15 11)"/>
            </svg>`
    },
    {
      name: "Google Chrome",
      bg: "#ffffff",
      svg: `<svg viewBox="0 0 24 24" width="28" height="28">
              <circle cx="12" cy="12" r="10" fill="#EA4335"/>
              <path d="M12 12 L22 12 A10 10 0 0 1 7 20.6 Z" fill="#34A853"/>
              <path d="M12 12 L7 20.6 A10 10 0 0 1 7 3.4 Z" fill="#FBBC05"/>
              <circle cx="12" cy="12" r="5" fill="#ffffff"/>
              <circle cx="12" cy="12" r="4" fill="#4285F4"/>
            </svg>`
    },
    {
      name: "Messenger",
      bg: "linear-gradient(135deg, #00B2FE 0%, #006AFF 50%, #B000FF 100%)",
      svg: `<svg viewBox="0 0 24 24" width="26" height="26" fill="#ffffff">
              <path d="M12 2C6.36 2 2 6.13 2 11.7c0 2.91 1.19 5.43 3.16 7.15V22l3.03-1.66c1.19.33 2.47.52 3.81.52 5.64 0 10-4.13 10-9.7S17.64 2 12 2zm1.05 13.06l-2.67-2.85-5.21 2.85 5.73-6.09 2.74 2.85 5.14-2.85-5.73 6.09z"/>
            </svg>`
    },
    {
      name: "Google Calendar",
      bg: "#ffffff",
      svg: `<div style="display:flex; flex-direction:column; align-items:center; width:100%; height:100%; justify-content:center; padding: 2px 0;">
              <span style="font-size:8px; font-weight:800; color:#1a73e8; text-transform:uppercase; line-height:1; letter-spacing:0.5px;">CAL</span>
              <span style="font-size:18px; font-weight:900; color:#1a73e8; line-height:1.1;">31</span>
            </div>`
    },
    {
      name: "VS Code",
      bg: "#1E1E1E",
      svg: `<svg viewBox="0 0 24 24" width="26" height="26" fill="#007ACC">
              <path d="M17.5 2.5l4.5 2.2v14.6l-4.5 2.2-10-8.5 7-5.5-7-5.5 10 8.5zm-5 13l-4 3.5-6.5-5 6.5-5 4 3.5-3.5 1.5 3.5 1.5z"/>
            </svg>`
    },
    {
      name: "ChatGPT",
      bg: "#000000",
      svg: `<svg viewBox="0 0 24 24" width="26" height="26" fill="#10A37F">
              <path d="M20.5 10.5a4.8 4.8 0 00-.4-3.4 5 5 0 00-4.3-2.5 4.8 4.8 0 00-3.3.4 5 5 0 00-6 1.8 4.8 4.8 0 00-1.8 3.3 5 5 0 00.5 6.2 4.8 4.8 0 00.4 3.4 5 5 0 004.3 2.5 4.8 4.8 0 003.3-.4 5 5 0 006-1.8 4.8 4.8 0 001.8-3.3 5 5 0 00-.5-6.2zm-7.6 10.1a3.6 3.6 0 01-2.2-.8l1.7-1a.6.6 0 00.3-.5v-4.1l3.5 2v2.2a3.7 3.7 0 01-3.3 2.2zm-6.7-3.8a3.7 3.7 0 01-.5-2.3l1.7 1a.6.6 0 00.6 0l3.5-2v4.1l-1.9 1.1a3.7 3.7 0 01-3.4-1.9zm-1.1-7.2a3.6 3.6 0 011.7-1.5v2a.6.6 0 00.3.5l3.5 2-3.5 2v-2.2a3.7 3.7 0 01-2-2.8zm11 1.7l-3.5-2v-4.1l1.9-1.1a3.7 3.7 0 013.4 1.9 3.6 3.6 0 01.5 2.3l-1.7-1a.6.6 0 00-.6 0zm2.2 4.9a3.7 3.7 0 01-1.7 1.5v-2a.6.6 0 00-.3-.5l-3.5-2 3.5-2v2.2a3.7 3.7 0 012 2.8zm-7.5-3.3l1.7-1 1.7 1v2l-1.7 1-1.7-1v-2z"/>
            </svg>`
    },
    {
      name: "Google Drive",
      bg: "#ffffff",
      svg: `<svg viewBox="0 0 24 24" width="26" height="26">
              <path d="M8.5 3.5l7 12H23l-7-12z" fill="#FFC107"/>
              <path d="M1 21.5h15l3.5-6H4.5z" fill="#2196F3"/>
              <path d="M8.5 3.5L1 15.5l3.5 6 7.5-12z" fill="#4CAF50"/>
            </svg>`
    },
    {
      name: "WhatsApp",
      bg: "#25D366",
      svg: `<svg viewBox="0 0 24 24" width="28" height="28" fill="#ffffff">
              <path d="M12 2C6.5 2 2 6.5 2 12c0 1.9.5 3.6 1.4 5.1L2 22l5.1-1.3C8.5 21.5 10.2 22 12 22c5.5 0 10-4.5 10-10S17.5 2 12 2zm5.7 14.3c-.2.7-1.3 1.3-1.8 1.4-.5.1-1.1.1-3.6-.9-3.2-1.3-5.2-4.5-5.3-4.7-.2-.2-1.2-1.6-1.2-3.1 0-1.5.8-2.2 1-2.5.3-.3.6-.4.9-.4.2 0 .4 0 .6.1.2.1.5.7.7 1.2.2.5.4 1 .4 1.1 0 .2 0 .4-.1.6-.1.2-.2.3-.3.5-.2.2-.3.3-.4.5-.1.2-.3.4-.1.7.2.4.9 1.5 1.9 2.4 1.3 1.2 2.4 1.5 2.8 1.7.3.2.6.2.8 0 .3-.3.9-1 1.1-1.4.2-.4.5-.3.8-.2.3.1 2.1 1 2.5 1.2.4.2.6.3.7.5.1.2.1 1.2-.1 1.9z"/>
            </svg>`
    },
    {
      name: "Linear",
      bg: "#12151B",
      svg: `<svg viewBox="0 0 24 24" width="24" height="24" fill="#ffffff">
              <path d="M3.2 4.6l9.6 14.8c.4.6 1.3.6 1.7 0l6.3-9.7c.4-.6.4-1.4 0-2L14.5 2.3c-.4-.6-1.3-.6-1.7 0L3.2 4.6zm8.8 11.2L6.1 6.8l4.9-.8 5 7.7-4 2.1z"/>
            </svg>`
    },
    {
      name: "Arc Browser",
      bg: "#ffffff",
      svg: `<svg viewBox="0 0 24 24" width="28" height="28">
              <circle cx="12" cy="12" r="10" fill="none" stroke="#FF4D4D" stroke-width="3"/>
              <circle cx="12" cy="12" r="7" fill="none" stroke="#FFB800" stroke-width="2.5"/>
              <circle cx="12" cy="12" r="4" fill="#3B82F6"/>
            </svg>`
    },
    {
      name: "Slack",
      bg: "#ffffff",
      svg: `<svg viewBox="0 0 24 24" width="26" height="26">
              <path d="M5.5 10.5a2 2 0 110-4 2 2 0 010 4zm0 2h4a2 2 0 110 4h-4a2 2 0 010-4z" fill="#E01E5A"/>
              <path d="M13.5 5.5a2 2 0 114 0 2 2 0 01-4 0zm-2 0v4a2 2 0 11-4 0v-4a2 2 0 014 0z" fill="#36C5F0"/>
              <path d="M18.5 13.5a2 2 0 110 4 2 2 0 010-4zm0-2h-4a2 2 0 110-4h4a2 2 0 010 4z" fill="#2EB67D"/>
              <path d="M10.5 18.5a2 2 0 11-4 0 2 2 0 014 0zm2 0v-4a2 2 0 114 0v4a2 2 0 01-4 0z" fill="#ECB22E"/>
            </svg>`
    },
    {
      name: "Gmail",
      bg: "#ffffff",
      svg: `<svg viewBox="0 0 24 24" width="26" height="26">
              <path d="M3 6l9 6.5L21 6v12a2 2 0 01-2 2H5a2 2 0 01-2-2V6z" fill="#F1F3F4"/>
              <path d="M3 6l9 6.5L21 6" fill="none" stroke="#EA4335" stroke-width="2.5"/>
              <path d="M3 6v12h4V10.5L3 6z" fill="#4285F4"/>
              <path d="M21 6v12h-4V10.5L21 6z" fill="#34A853"/>
              <path d="M7 18h10V9L12 12.5 7 9v9z" fill="#FBBC04"/>
            </svg>`
    },
    {
      name: "Notion",
      bg: "#ffffff",
      svg: `<svg viewBox="0 0 24 24" width="26" height="26">
              <path d="M4.5 4l12.5-1.5 2.5 2v14.5l-13.5 1.5-2.5-2V4zm3 3.5v9l2.5-.5V8.5l6 8 2.5-.5v-9l-2.5.5v7.5l-6-8-2.5.5z" fill="#000000"/>
            </svg>`
    },
    {
      name: "Google Docs",
      bg: "#4285F4",
      svg: `<svg viewBox="0 0 24 24" width="26" height="26" fill="#ffffff">
              <path d="M6 3h8l5 5v12a2 2 0 01-2 2H6a2 2 0 01-2-2V5a2 2 0 012-2z"/>
              <path d="M14 3v5h5" fill="#A1C2FA"/>
              <path d="M8 12h8m-8 3h8m-8 3h5" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round"/>
            </svg>`
    },
    {
      name: "Figma",
      bg: "#1E1E1E",
      svg: `<svg viewBox="0 0 24 24" width="24" height="24">
              <rect x="7" y="3" width="5" height="5" rx="2.5" fill="#F24E1E"/>
              <rect x="12" y="3" width="5" height="5" rx="2.5" fill="#FF7262"/>
              <rect x="7" y="8" width="5" height="5" rx="2.5" fill="#A259FF"/>
              <circle cx="14.5" cy="10.5" r="2.5" fill="#1ABCFE"/>
              <path d="M7 13h5v2.5a2.5 2.5 0 01-5 0V13z" fill="#0ACF83"/>
            </svg>`
    },
    {
      name: "Spotify",
      bg: "#1DB954",
      svg: `<svg viewBox="0 0 24 24" width="26" height="26" fill="#000000">
              <circle cx="12" cy="12" r="10" fill="#1DB954"/>
              <path d="M7 9.5c3.5-1 7.5-.7 10.5 1m-10 3c3-.8 6.5-.5 9 1m-8.5 3c2.3-.5 5-.3 7 .8" stroke="#000000" stroke-width="1.8" stroke-linecap="round" fill="none"/>
            </svg>`
    },
    {
      name: "GitHub",
      bg: "#24292E",
      svg: `<svg viewBox="0 0 24 24" width="26" height="26" fill="#ffffff">
              <path d="M12 2C6.48 2 2 6.48 2 12c0 4.42 2.87 8.17 6.84 9.5.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34-.46-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.87 1.52 2.34 1.07 2.91.83.1-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.92 0-1.11.38-2 1.03-2.71-.1-.25-.45-1.29.1-2.64 0 0 .84-.27 2.75 1.02.79-.22 1.65-.33 2.5-.33.85 0 1.71.11 2.5.33 1.91-1.29 2.75-1.02 2.75-1.02.55 1.35.2 2.39.1 2.64.65.71 1.03 1.6 1.03 2.71 0 3.82-2.34 4.66-4.57 4.91.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0012 2z"/>
            </svg>`
    },
    {
      name: "Apple Notes",
      bg: "#ffffff",
      svg: `<div style="display:flex; flex-direction:column; width:100%; height:100%; border-radius:12px; overflow:hidden;">
              <div style="background:#FFCC00; height:10px; width:100%;"></div>
              <div style="padding:4px 6px; display:flex; flex-direction:column; gap:3px;">
                <div style="height:2px; background:#e5e5ea; width:90%; border-radius:1px;"></div>
                <div style="height:2px; background:#e5e5ea; width:70%; border-radius:1px;"></div>
                <div style="height:2px; background:#e5e5ea; width:80%; border-radius:1px;"></div>
              </div>
            </div>`
    }
  ];

  function initSnakeAnimation() {
    const container = document.getElementById('snakeTrackContainer');
    const path = document.getElementById('snakeCurvePath');
    if (!container || !path) return;

    // Clear previous icons if any
    const existing = container.querySelectorAll('.snake-app-icon');
    existing.forEach(el => el.remove());

    const totalPathLength = path.getTotalLength();
    const spacing = 68; // Spacing along path

    // Create DOM nodes for icons
    const iconNodes = APP_ICONS.map((app, index) => {
      const el = document.createElement('div');
      el.className = 'snake-app-icon';
      el.title = app.name;
      el.style.background = app.bg;
      el.innerHTML = app.svg;
      container.appendChild(el);
      return {
        el,
        baseOffset: index * spacing
      };
    });

    let currentScroll = 0;
    const speed = 0.85; // Pixels per frame

    function animate() {
      currentScroll += speed;
      const effectiveLength = totalPathLength + (spacing * 2);

      // Sizing ratio for responsiveness against viewBox 1140 x 440
      const containerW = container.clientWidth || 1140;
      const containerH = container.clientHeight || 440;
      const scaleX = containerW / 1140;
      const scaleY = containerH / 440;

      iconNodes.forEach(item => {
        // Calculate distance along path with seamless wrapping
        let dist = (item.baseOffset + currentScroll) % effectiveLength - spacing;
        
        // Clamp query to valid path length
        const queryDist = Math.max(0, Math.min(totalPathLength, dist));
        const pt = path.getPointAtLength(queryDist);
        
        // Tangent angle
        const delta = 2;
        const ptNext = path.getPointAtLength(Math.min(totalPathLength, queryDist + delta));
        const angle = Math.atan2((ptNext.y - pt.y) * scaleY, (ptNext.x - pt.x) * scaleX) * (180 / Math.PI);

        // Opacity fade at the far edges
        let opacity = 1;
        if (dist < 40) {
          opacity = Math.max(0, dist / 40);
        } else if (dist > totalPathLength - 40) {
          opacity = Math.max(0, (totalPathLength - dist) / 40);
        }

        const x = pt.x * scaleX;
        const y = pt.y * scaleY;

        // Apply hardware-accelerated 3D transform with slight tilt along ribbon
        item.el.style.transform = `translate3d(${x - 26}px, ${y - 26}px, 0) rotate(${angle * 0.75}deg)`;
        item.el.style.opacity = opacity;
      });

      requestAnimationFrame(animate);
    }

    requestAnimationFrame(animate);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initSnakeAnimation);
  } else {
    initSnakeAnimation();
  }
})();
