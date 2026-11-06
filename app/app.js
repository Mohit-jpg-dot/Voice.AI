// ==========================================================================
// Voice.AI Desktop Agent Runtime v3.2
// ADD-ON: Continuous Notch Glass Island + Circle to Ask Screen Context
// ==========================================================================

const Voice.AIState = {
  activeNavTab: 'dashboard',
  isIslandExpanded: false,
  isPinned: false,
  isDrawerOpen: false,
  isAppBuilderOpen: false,
  isScreenCaptureActive: false,
  activeSelectionTool: 'lasso', // 'lasso' | 'rectangle' | 'element' | 'window'
  
  voiceMode: 'idle', // 'idle' | 'listening' | 'thinking' | 'executing'
  triggerMode: 'Agent Mode',
  
  // Profile & Metrics
  userName: 'Jonah Daian',
  userEmail: 'jonah@wako.ai',
  trialDaysUsed: 0,
  trialDaysTotal: 14,
  totalSessions: 47,
  totalWords: 819,
  timeSavedMinutes: 15,

  // Current Notch Action
  currentSession: {
    prompt: "Add a task to my Field Productive project to review the thumbnail concepts.",
    agentReply: "I drafted a task to review thumbnail concepts, have a look.",
    action: {
      app: "Things 3",
      title: "Review thumbnail concepts",
      list: "Feel Productive",
      due: "Today",
      isApproved: false
    }
  },

  // Active Circle to Ask Crop
  activeCrop: null,

  // Threads History
  history: [
    {
      id: "h1",
      app: "Slack",
      icon: "#",
      color: "#E01E5A",
      prompt: "Product Hunt Comment drafts review",
      displayPrompt: "Product Hunt Comment ...",
      reply: "Prepared comments for top productive launches."
    },
    {
      id: "h2",
      app: "Google Calendar",
      icon: "31",
      color: "#4285F4",
      prompt: "Product Launch and Roadmap review",
      displayPrompt: "Product Launch and Roa...",
      reply: "Scheduled Roadmap Discussion with Kai & Maxim."
    },
    {
      id: "h3",
      app: "Browser",
      icon: "🌐",
      color: "#007AFF",
      prompt: "Hey, can you check my inbox for urgent leads?",
      displayPrompt: "Hey, can you check my i...",
      reply: "2 priority emails identified from beta testers."
    },
    {
      id: "h4",
      app: "Slack",
      icon: "#",
      color: "#E01E5A",
      prompt: "Product Hunt Launch Coordination",
      displayPrompt: "Product Hunt Launch Co...",
      reply: "Updated the core release channel on Slack."
    },
    {
      id: "h5",
      app: "Slack",
      icon: "#",
      color: "#E01E5A",
      prompt: "Product Hunt Launch Coordination",
      displayPrompt: "Product Hunt Launch Co...",
      reply: "Drafted social copy for the release."
    },
    {
      id: "h6",
      app: "Browser",
      icon: "🌐",
      color: "#007AFF",
      prompt: "Hey, can you check my inbox for urgent leads?",
      displayPrompt: "Hey, can you check my i...",
      reply: "Found inbound demo request from Seed stage fund."
    },
    {
      id: "h7",
      app: "Slack",
      icon: "#",
      color: "#E01E5A",
      prompt: "Product Hunt Launch Coordination",
      displayPrompt: "Product Hunt Launch Co...",
      reply: "Synced with engineering on hotfix deploy."
    },
    {
      id: "h8",
      app: "Browser",
      icon: "🌐",
      color: "#007AFF",
      prompt: "Hey, can you check my inbox for urgent leads?",
      displayPrompt: "Hey, can you check my i...",
      reply: "Checked Gmail and Outlook accounts."
    },
    {
      id: "h9",
      app: "Slack",
      icon: "#",
      color: "#E01E5A",
      prompt: "Product Hunt Launch Coordination",
      displayPrompt: "Product Hunt Launch Co...",
      reply: "Posted announcement to #general."
    },
    {
      id: "h10",
      app: "Gmail",
      icon: "M",
      color: "#EA4335",
      prompt: "Urgent Email Review",
      displayPrompt: "Urgent Email Review",
      reply: "Archived newsletter notifications and highlighted CEO email."
    },
    {
      id: "h11",
      app: "Gmail",
      icon: "M",
      color: "#EA4335",
      prompt: "Urgent Email Review",
      displayPrompt: "Urgent Email Review",
      reply: "Flagged contract amendment from legal team."
    }
  ],

  // Connected Apps
  connectedApps: [
    {
      id: "yt",
      name: "YouTube Studio",
      desc: "Check YouTube subscriber counts, recent videos and analytics.",
      icon: "▶",
      color: "#FF0000",
      enabled: true
    },
    {
      id: "things",
      name: "Things 3",
      desc: "Add, check off, and view your tasks in any project or inbox.",
      icon: "✓",
      color: "#007AFF",
      enabled: true
    },
    {
      id: "slack",
      name: "Slack",
      desc: "Read unread messages, send updates, and search project channels.",
      icon: "#",
      color: "#4A154B",
      enabled: false
    },
    {
      id: "gcal",
      name: "Google Calendar",
      desc: "Check schedule, schedule new meetings, and send invites.",
      icon: "📅",
      color: "#4285F4",
      enabled: false
    }
  ]
};

// DOM References
const notchIsland = document.getElementById('notchGlassIsland');
const islandInput = document.getElementById('islandInput');
const btnMicToggle = document.getElementById('btnMicToggle');
const btnPinIsland = document.getElementById('btnPinIsland');
const btnCollapseIsland = document.getElementById('btnCollapseIsland');
const btnCircleTrigger = document.getElementById('btnCircleTrigger');
const captureIndicator = document.getElementById('captureIndicator');

const circleCropPreview = document.getElementById('circleCropPreview');
const cropOcrText = document.getElementById('cropOcrText');
const cropToolBadge = document.getElementById('cropToolBadge');
const redactionBadge = document.getElementById('redactionBadge');

const bgStatusChip = document.getElementById('bgStatusChip');
const bgStatusText = document.getElementById('bgStatusText');
const deepLinkCard = document.getElementById('deepLinkCard');
const deepLinkIcon = document.getElementById('deepLinkIcon');
const deepLinkTitle = document.getElementById('deepLinkTitle');
const deepLinkElapsed = document.getElementById('deepLinkElapsed');
const deepLinkBtn = document.getElementById('deepLinkBtn');

const tabMyApps = document.getElementById('tabMyApps');
const tabConnectors = document.getElementById('tabConnectors');
const sectionMyApps = document.getElementById('sectionMyApps');
const sectionConnectors = document.getElementById('sectionConnectors');
const connectorsList = document.getElementById('connectorsList');
const permissionsTable = document.getElementById('permissionsTable');

const screenOverlay = document.getElementById('screenSelectionOverlay');
const selectionCanvas = document.getElementById('selectionCanvas');
const selectionToolbar = document.getElementById('selectionToolbar');
const cancelSelectionBtn = document.getElementById('cancelSelectionBtn');

const historyDrawer = document.getElementById('historyDrawer');
const modalOverlay = document.getElementById('modalOverlay');
const toastNotice = document.getElementById('toastNotice');
const actionConfirmBtn = document.getElementById('actionConfirmBtn');
const actionCheckbox = document.getElementById('actionCheckbox');
const dialogUserPrompt = document.getElementById('dialogUserPrompt');
const dialogAgentReply = document.getElementById('dialogAgentReply');
const islandStateDot = document.getElementById('islandStateDot');
const islandStateBadge = document.getElementById('islandStateBadge');

const totalSessionsEl = document.getElementById('totalSessions');
const totalWordsEl = document.getElementById('totalWords');
const timeSavedEl = document.getElementById('timeSaved');
const drawerThreadsList = document.getElementById('drawerThreadsList');
const drawerSearchInput = document.getElementById('drawerSearchInput');
const appsGrid = document.getElementById('appsGrid');

// Connector Registry Data (11 Verified Connectors)
const VerifiedConnectors = [
  // Music & Media
  { id: "spotify", name: "Spotify", method: "AppleScript / Spotify Web API", color: "#1DB954", icon: "🎵", actions: ["play_playlist", "pause", "resume", "search_track"] },
  { id: "youtube", name: "YouTube", method: "YouTube Data API v3", color: "#FF0000", icon: "▶️", actions: ["search_video", "play_video", "stats"] },

  // Communication
  { id: "gmail", name: "Gmail", method: "Gmail REST API (Minimal)", color: "#EA4335", icon: "✉️", actions: ["draft_email", "list_unread", "search"] },
  { id: "outlook", name: "Microsoft Outlook", method: "Microsoft Graph REST API", color: "#0078D4", icon: "📧", actions: ["read_emails", "draft_reply", "calendar_events"] },
  { id: "slack", name: "Slack", method: "Slack Web API", color: "#4A154B", icon: "💬", actions: ["post_message", "list_channels"] },
  { id: "discord", name: "Discord", method: "Discord Bot API", color: "#5865F2", icon: "👾", actions: ["send_message", "get_status"] },
  { id: "x_twitter", name: "X / Twitter", method: "X API v2 / Browser Profile", color: "#000000", icon: "𝕏", actions: ["post_tweet", "check_notifications", "search_tweets"] },

  // Productivity & Notes
  { id: "notes", name: "Apple Notes", method: "AppleScript / Shortcuts", color: "#E4B622", icon: "📝", actions: ["create_note", "append_note"] },
  { id: "notion", name: "Notion", method: "Notion API & MCP Client", color: "#000000", icon: "⬛", actions: ["add_page", "query_database"] },
  { id: "obsidian", name: "Obsidian", method: "Obsidian URI / Markdown Vault", color: "#7C3AED", icon: "📓", actions: ["create_note", "search_notes", "append_daily_note"] },
  { id: "google_drive", name: "Google Drive", method: "Google Drive API v3", color: "#34A853", icon: "📁", actions: ["search_files", "open_doc", "summarize_file"] },
  { id: "canvas_lms", name: "Canvas LMS", method: "Canvas LMS REST API", color: "#E02424", icon: "🎓", actions: ["list_assignments", "upcoming_deadlines", "grades_summary"] },
  { id: "google_maps", name: "Google Maps", method: "Google Places API / URL Scheme", color: "#4285F4", icon: "🗺️", actions: ["search_places", "directions", "eta_saved_location"] },

  // Developer & Trackers
  { id: "linear", name: "Linear", method: "Linear GraphQL API / Webhooks", color: "#5E6AD2", icon: "📐", actions: ["create_issue", "list_my_issues", "update_cycle"] },
  { id: "jira", name: "Jira Software", method: "Atlassian Jira REST API v3", color: "#0052CC", icon: "🔷", actions: ["create_ticket", "transition_status", "log_work"] },
  { id: "github", name: "GitHub", method: "gh CLI / GitHub API", color: "#24292E", icon: "🐙", actions: ["list_prs", "view_issues"] },
  { id: "vscode", name: "VS Code", method: "code CLI & URI Scheme", color: "#007ACC", icon: "💻", actions: ["open_project", "jump_to_file"] },

  // Native Apple Ecosystem
  { id: "apple_mail", name: "Apple Mail", method: "AppleScript & Mail App Intents", color: "#007AFF", icon: "📫", actions: ["create_mail", "check_inbox", "search_messages"] },
  { id: "apple_imessage", name: "Apple iMessage", method: "Messages App Intents & AppleScript", color: "#34C759", icon: "💬", actions: ["send_message", "read_last_message"] },
  { id: "apple_reminders", name: "Apple Reminders", method: "EventKit & Shortcuts Intents", color: "#FF9500", icon: "🔔", actions: ["add_reminder", "list_today", "complete_reminder"] },
  { id: "apple_finder", name: "Apple Finder", method: "AppleScript & POSIX File System", color: "#007AFF", icon: "📂", actions: ["reveal_folder", "find_recent_files", "move_file"] },
  { id: "apple_calendar", name: "Apple Calendar", method: "EventKit & Calendar Intents", color: "#FF3B30", icon: "📅", actions: ["add_event", "show_schedule", "next_meeting"] },

  // Browsers & AI Relay
  { id: "browser", name: "Safari / Chrome / Arc", method: "Background Profile", color: "#007AFF", icon: "🌐", actions: ["open_tab", "search_query"] },
  { id: "ai_relay", name: "ChatGPT / Claude Relay", method: "Isolated Profile / API", color: "#74AA9C", icon: "✨", actions: ["ask_chatgpt", "ask_claude"] }
];

// Remembered Permissions Data
let RememberedGrants = [
  { id: "p1", app: "Spotify", capability: "playback_control", account: "jonah@wako.ai", expiry: "Always", risk: "low" },
  { id: "p2", app: "GitHub", capability: "read_prs_and_issues", account: "jonahdaian", expiry: "Always", risk: "low" },
  { id: "p3", app: "Slack", capability: "post_message", account: "wako.slack.com", expiry: "For today", risk: "medium" }
];

// ==========================================================================
// CONTINUOUS NOTCH ISLAND MORPHING & HOVER
// ==========================================================================
let hoverTimeout = null;

function expandIsland() {
  clearTimeout(hoverTimeout);
  Voice.AIState.isIslandExpanded = true;
  notchIsland.classList.add('expanded');
}

function collapseIsland(force = false) {
  if (Voice.AIState.isPinned && !force) return;
  // Don't collapse if user is actively typing in the input
  if (document.activeElement === islandInput && !force) return;

  clearTimeout(hoverTimeout);
  hoverTimeout = setTimeout(() => {
    Voice.AIState.isIslandExpanded = false;
    notchIsland.classList.remove('expanded');
  }, 220);
}

// Hover event listeners on the continuous notch island
notchIsland.addEventListener('mouseenter', () => {
  expandIsland();
});

notchIsland.addEventListener('mouseleave', () => {
  collapseIsland();
});

// Click to toggle when resting
notchIsland.addEventListener('click', (e) => {
  if (!Voice.AIState.isIslandExpanded) {
    expandIsland();
  }
});

// Pin toggle
btnPinIsland.addEventListener('click', (e) => {
  e.stopPropagation();
  Voice.AIState.isPinned = !Voice.AIState.isPinned;
  btnPinIsland.classList.toggle('pinned', Voice.AIState.isPinned);
  btnPinIsland.title = Voice.AIState.isPinned ? "Unpin Island" : "Pin Island Open";
  showToast(Voice.AIState.isPinned ? "Notch Island Pinned Open" : "Notch Island Unpinned");
});

// Manual Collapse button
btnCollapseIsland.addEventListener('click', (e) => {
  e.stopPropagation();
  Voice.AIState.isPinned = false;
  btnPinIsland.classList.remove('pinned');
  collapseIsland(true);
});

// Unified Typing in Island Input
islandInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    e.preventDefault();
    const val = islandInput.value.trim();
    if (val) {
      submitUserPrompt(val);
      islandInput.value = '';
    }
  }
});

function submitUserPrompt(promptText) {
  dialogUserPrompt.textContent = promptText;
  expandIsland();
  
  const startTime = performance.now();
  const lower = promptText.toLowerCase();

  // Check voice revoke
  if (lower.includes("permission hata do") || lower.includes("revoke permission")) {
    if (lower.includes("slack")) {
      RememberedGrants = RememberedGrants.filter(g => g.app.toLowerCase() !== "slack");
      renderPermissionsTable();
      dialogAgentReply.textContent = "Boss, Slack ki permissions revoke kar di hain. Agli baar approval mangunga.";
      showToast("Slack permissions revoked by voice");
      return;
    }
  }

  // Show non-intrusive background execution status chip
  bgStatusChip.style.display = 'flex';
  bgStatusText.textContent = "Running background task (no focus stolen)...";
  setIslandState('thinking');
  deepLinkCard.style.display = 'none';

  setTimeout(() => {
    const elapsed = ((performance.now() - startTime) / 1000).toFixed(1);
    setIslandState('idle');
    bgStatusChip.style.display = 'none';

    // 1. Spotify
    if (lower.includes("spotify") || lower.includes("playlist") || lower.includes("gaana")) {
      dialogAgentReply.textContent = `Ho gaya, Boss. Spotify pe chill playlist laga di hai. (${elapsed} seconds)`;
      deepLinkCard.style.display = 'flex';
      deepLinkIcon.textContent = "🎵";
      deepLinkTitle.textContent = "Spotify: Chill Vibes Playlist";
      deepLinkElapsed.textContent = `Measured time: ${elapsed}s (AppleScript)`;
      deepLinkBtn.href = "https://open.spotify.com";
      deepLinkBtn.textContent = "View in Spotify ↗";
      showToast(`Spotify task completed in ${elapsed}s`);
    }
    // 2. Slack
    else if (lower.includes("slack") || lower.includes("bata do") || lower.includes("meeting late")) {
      dialogAgentReply.textContent = `Ho gaya, Boss. Slack pe team ko update bhej diya: "meeting late hai". (${elapsed} seconds)`;
      deepLinkCard.style.display = 'flex';
      deepLinkIcon.textContent = "💬";
      deepLinkTitle.textContent = "Slack: #general team message";
      deepLinkElapsed.textContent = `Measured time: ${elapsed}s (Web API)`;
      deepLinkBtn.href = "https://slack.com";
      deepLinkBtn.textContent = "View in Slack ↗";
      showToast(`Slack update posted in ${elapsed}s`);
    }
    // 3. GitHub
    else if (lower.includes("github") || lower.includes("pr") || lower.includes("pull request")) {
      dialogAgentReply.textContent = `Boss, 3 open PRs hain Voice.AI repo pe. Review ke liye ready hain. (${elapsed} seconds)`;
      deepLinkCard.style.display = 'flex';
      deepLinkIcon.textContent = "🐙";
      deepLinkTitle.textContent = "GitHub: 3 Open PRs (#142, #145, #148)";
      deepLinkElapsed.textContent = `Measured time: ${elapsed}s (gh CLI)`;
      deepLinkBtn.href = "https://github.com";
      deepLinkBtn.textContent = "View on GitHub ↗";
      showToast(`GitHub PRs fetched in ${elapsed}s`);
    }
    // 4. Search
    else if (lower.includes("search") || lower.includes("dhoondo")) {
      const q = promptText.replace(/search karo:?/i, '').replace(/search/i, '').trim();
      dialogAgentReply.textContent = `Boss, search complete for "${q}". Top 3 verified sources summarized. (${elapsed} seconds)`;
      deepLinkCard.style.display = 'flex';
      deepLinkIcon.textContent = "🔍";
      deepLinkTitle.textContent = `Google Search: "${q.slice(0, 24)}..."`;
      deepLinkElapsed.textContent = `Measured time: ${elapsed}s (Sourced)`;
      deepLinkBtn.href = `https://www.google.com/search?q=${encodeURIComponent(q)}`;
      deepLinkBtn.textContent = "View Sources ↗";
      showToast(`Search completed in ${elapsed}s`);
    }
    // Default
    else {
      dialogAgentReply.textContent = `Ho gaya, Boss. Task executed in ${elapsed} seconds.`;
      deepLinkCard.style.display = 'none';
    }

    Voice.AIState.totalSessions += 1;
    Voice.AIState.totalWords += promptText.split(' ').length;
    Voice.AIState.timeSavedMinutes += 1;
    
    totalSessionsEl.textContent = Voice.AIState.totalSessions;
    totalWordsEl.textContent = Voice.AIState.totalWords;
    timeSavedEl.textContent = `${Voice.AIState.timeSavedMinutes}m`;
  }, 1300);
}

function setIslandState(state) {
  Voice.AIState.voiceMode = state;
  switch (state) {
    case 'listening':
      islandStateDot.style.background = '#38bdf8';
      islandStateBadge.textContent = 'Listening';
      islandStateBadge.style.color = '#38bdf8';
      btnMicToggle.classList.add('recording');
      break;
    case 'thinking':
      islandStateDot.style.background = '#ff9f0a';
      islandStateBadge.textContent = 'Thinking';
      islandStateBadge.style.color = '#ff9f0a';
      btnMicToggle.classList.remove('recording');
      break;
    case 'executing':
      islandStateDot.style.background = '#af52de';
      islandStateBadge.textContent = 'Executing';
      islandStateBadge.style.color = '#af52de';
      btnMicToggle.classList.remove('recording');
      break;
    default:
      islandStateDot.style.background = '#34c759';
      islandStateBadge.textContent = 'Active';
      islandStateBadge.style.color = '#38bdf8';
      btnMicToggle.classList.remove('recording');
      break;
  }
}

// Voice Toggle on Island Mic
btnMicToggle.addEventListener('click', (e) => {
  e.stopPropagation();
  if (Voice.AIState.voiceMode === 'listening') {
    finishVoiceInput();
  } else {
    startVoiceInput('Agent Mode');
  }
});

function startVoiceInput(modeName) {
  expandIsland();
  setIslandState('listening');
  dialogUserPrompt.textContent = "Listening to speech...";
  
  // Real or simulated speech
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (SpeechRecognition) {
    try {
      const rec = new SpeechRecognition();
      rec.continuous = false;
      rec.interimResults = true;
      rec.onresult = (evt) => {
        dialogUserPrompt.textContent = Array.from(evt.results).map(r => r[0].transcript).join('');
      };
      rec.onend = () => finishVoiceInput();
      rec.onerror = () => simulateVoiceSpeech();
      rec.start();
      return;
    } catch (e) {}
  }
  simulateVoiceSpeech();
}

function simulateVoiceSpeech() {
  setTimeout(() => {
    finishVoiceInput();
  }, 2200);
}

function finishVoiceInput() {
  setIslandState('thinking');
  dialogAgentReply.textContent = "Synthesizing answer...";
  setTimeout(() => {
    setIslandState('idle');
    dialogAgentReply.textContent = "I drafted a task to review thumbnail concepts, have a look.";
    actionConfirmBtn.classList.remove('done');
    actionConfirmBtn.textContent = 'Add to-do';
    showToast("Voice command processed");
  }, 600);
}

// ==========================================================================
// CIRCLE TO ASK (Screen Selection Engine)
// ==========================================================================
let isDrawing = false;
let startX = 0, startY = 0;
let points = [];
const ctx = selectionCanvas.getContext('2d');

function resizeCanvas() {
  selectionCanvas.width = window.innerWidth;
  selectionCanvas.height = window.innerHeight;
}
window.addEventListener('resize', resizeCanvas);
resizeCanvas();

btnCircleTrigger.addEventListener('click', (e) => {
  e.stopPropagation();
  triggerCircleToAsk();
});

function triggerCircleToAsk() {
  Voice.AIState.isScreenCaptureActive = true;
  screenOverlay.classList.add('active');
  captureIndicator.classList.add('active');
  collapseIsland(true);
  ctx.clearRect(0, 0, selectionCanvas.width, selectionCanvas.height);
  showToast("Circle or drag anywhere on screen to Ask");
}

function closeCircleToAsk() {
  Voice.AIState.isScreenCaptureActive = false;
  screenOverlay.classList.remove('active');
  captureIndicator.classList.remove('active');
  isDrawing = false;
  points = [];
  ctx.clearRect(0, 0, selectionCanvas.width, selectionCanvas.height);
}

cancelSelectionBtn.addEventListener('click', () => {
  closeCircleToAsk();
});

// Selection Tool Switching
document.querySelectorAll('.selection-tool-btn').forEach(btn => {
  btn.addEventListener('click', (e) => {
    e.stopPropagation();
    document.querySelectorAll('.selection-tool-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    Voice.AIState.activeSelectionTool = btn.dataset.tool;

    if (Voice.AIState.activeSelectionTool === 'window') {
      completeCapture({ x: 100, y: 100, width: 800, height: 500 }, 'Whole Window');
    }
  });
});

// Canvas Drawing Events
selectionCanvas.addEventListener('mousedown', (e) => {
  isDrawing = true;
  startX = e.clientX;
  startY = e.clientY;
  points = [{ x: startX, y: startY }];
});

selectionCanvas.addEventListener('mousemove', (e) => {
  if (!isDrawing) return;
  const curX = e.clientX;
  const curY = e.clientY;
  points.push({ x: curX, y: curY });

  ctx.clearRect(0, 0, selectionCanvas.width, selectionCanvas.height);

  if (Voice.AIState.activeSelectionTool === 'lasso') {
    // Draw glowing lasso path
    ctx.strokeStyle = '#38bdf8';
    ctx.lineWidth = 3;
    ctx.shadowColor = '#0071e3';
    ctx.shadowBlur = 10;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    ctx.moveTo(points[0].x, points[0].y);
    for (let i = 1; i < points.length; i++) {
      ctx.lineTo(points[i].x, points[i].y);
    }
    ctx.stroke();
  } else if (Voice.AIState.activeSelectionTool === 'rectangle' || Voice.AIState.activeSelectionTool === 'element') {
    // Draw glowing rectangle
    const w = curX - startX;
    const h = curY - startY;
    ctx.strokeStyle = '#38bdf8';
    ctx.lineWidth = 2;
    ctx.shadowColor = '#0071e3';
    ctx.shadowBlur = 8;
    ctx.strokeRect(startX, startY, w, h);
    ctx.fillStyle = 'rgba(56, 189, 248, 0.12)';
    ctx.fillRect(startX, startY, w, h);
  }
});

selectionCanvas.addEventListener('mouseup', (e) => {
  if (!isDrawing) return;
  isDrawing = false;
  
  let box = null;
  if (Voice.AIState.activeSelectionTool === 'lasso') {
    const xs = points.map(p => p.x);
    const ys = points.map(p => p.y);
    box = {
      x: Math.min(...xs),
      y: Math.min(...ys),
      width: Math.max(...xs) - Math.min(...xs),
      height: Math.max(...ys) - Math.min(...ys)
    };
  } else {
    box = {
      x: Math.min(startX, e.clientX),
      y: Math.min(startY, e.clientY),
      width: Math.abs(e.clientX - startX),
      height: Math.abs(e.clientY - startY)
    };
  }

  if (box.width > 15 && box.height > 15) {
    completeCapture(box, Voice.AIState.activeSelectionTool);
  } else {
    closeCircleToAsk();
  }
});

function completeCapture(box, toolName) {
  closeCircleToAsk();

  // Simulated OCR & Sensitive Redaction
  const rawContext = "Things 3 — Project Feel Productive: Review thumbnail redesign concepts (secret: sk-antigravity_token_7721). Client roadmap deadline due Today.";
  const redactedContext = rawContext.replace(/sk-[a-zA-Z0-9_]{15,}/g, '[REDACTED_API_KEY]');
  const redactionCount = 1;

  Voice.AIState.activeCrop = {
    box: box,
    tool: toolName,
    ocr: redactedContext,
    redactedCount: redactionCount
  };

  // Populate Crop Preview in the island
  circleCropPreview.classList.add('visible');
  cropToolBadge.textContent = toolName.toUpperCase();
  cropOcrText.textContent = redactedContext;
  
  if (redactionCount > 0) {
    redactionBadge.style.display = 'inline-block';
    redactionBadge.textContent = `${redactionCount} REDACTED`;
  } else {
    redactionBadge.style.display = 'none';
  }

  // Pre-fill query dialog
  dialogUserPrompt.textContent = "What is this selected content?";
  dialogAgentReply.textContent = `Selected region captured (${toolName}). Contains Things 3 task items. How would you like to process this?`;

  // Auto-expand Island
  expandIsland();
  showToast("Screen captured & context loaded into Notch Island");
}

// Quick Action Chips in Island
document.querySelectorAll('.action-chip').forEach(chip => {
  chip.addEventListener('click', () => {
    if (chip.dataset.query) {
      submitUserPrompt(chip.dataset.query);
      return;
    }
    const action = chip.dataset.action;
    dialogUserPrompt.textContent = `${chip.textContent} for the selected screen context`;
    setIslandState('thinking');
    
    setTimeout(() => {
      setIslandState('idle');
      switch (action) {
        case 'explain':
          dialogAgentReply.textContent = "This is a task management item from Things 3 regarding the 'Feel Productive' thumbnail concepts.";
          break;
        case 'translate':
          dialogAgentReply.textContent = "हिंदी अनुवाद: थंबनेल रीडिज़ाइन कॉन्सेप्ट्स की समीक्षा करें और कार्य को आज के लिए शेड्यूल करें।";
          break;
        case 'copy':
          navigator.clipboard.writeText(cropOcrText.textContent).catch(() => {});
          dialogAgentReply.textContent = "Extracted cleaned OCR text copied to system clipboard.";
          showToast("OCR text copied to clipboard");
          break;
        case 'things':
          dialogAgentReply.textContent = "I drafted a task in Things 3 based on your selection, have a look.";
          actionConfirmBtn.classList.remove('done');
          actionConfirmBtn.textContent = 'Add to-do';
          break;
      }
    }, 550);
  });
});

// Toast Helper
function showToast(message) {
  toastNotice.textContent = message;
  toastNotice.classList.add('show');
  setTimeout(() => toastNotice.classList.remove('show'), 2200);
}

// History Drawer Toggle
document.getElementById('drawerToggleBtn').addEventListener('click', (e) => {
  e.stopPropagation();
  Voice.AIState.isDrawerOpen = !Voice.AIState.isDrawerOpen;
  historyDrawer.classList.toggle('closed', !Voice.AIState.isDrawerOpen);
});

// Navigation Tabs Handling
document.querySelectorAll('.nav-item').forEach(item => {
  item.addEventListener('click', () => {
    document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
    item.classList.add('active');
    
    const tab = item.dataset.tab;
    Voice.AIState.activeNavTab = tab;
    
    document.querySelectorAll('.view-panel').forEach(panel => {
      panel.classList.remove('active');
    });
    
    const targetPanel = document.getElementById(`view-${tab}`);
    if (targetPanel) {
      targetPanel.classList.add('active');
    }
  });
});

// Approve Action Card (Things 3)
actionConfirmBtn.addEventListener('click', () => {
  if (actionConfirmBtn.classList.contains('done')) return;

  actionConfirmBtn.classList.add('done');
  actionConfirmBtn.textContent = 'Added ✓';
  actionCheckbox.classList.add('checked');
  
  // Update stats
  Voice.AIState.totalSessions += 1;
  Voice.AIState.totalWords += 14;
  Voice.AIState.timeSavedMinutes += 1;

  totalSessionsEl.textContent = Voice.AIState.totalSessions;
  totalWordsEl.textContent = Voice.AIState.totalWords;
  timeSavedEl.textContent = `${Voice.AIState.timeSavedMinutes}m`;

  // Prepend to history
  Voice.AIState.history.unshift({
    id: `h_${Date.now()}`,
    app: "Things 3",
    icon: "✓",
    color: "#007AFF",
    prompt: dialogUserPrompt.textContent,
    reply: "Added task to Things 3: Review thumbnail concepts."
  });

  renderHistoryDrawer();
  showToast('Task confirmed and saved to Things 3');
});

actionCheckbox.addEventListener('click', () => {
  actionCheckbox.classList.toggle('checked');
});

// Render History
function renderHistoryDrawer(filter = '') {
  drawerThreadsList.innerHTML = '';
  const filtered = Voice.AIState.history.filter(h => 
    h.prompt.toLowerCase().includes(filter.toLowerCase()) || 
    h.app.toLowerCase().includes(filter.toLowerCase())
  );

  filtered.forEach(item => {
    const el = document.createElement('div');
    el.className = 'thread-item';
    el.innerHTML = `
      <div class="thread-icon-badge" style="background: ${item.color}">${item.icon}</div>
      <div style="flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
        ${item.prompt}
      </div>
    `;
    el.addEventListener('click', () => {
      dialogUserPrompt.textContent = item.prompt;
      dialogAgentReply.textContent = item.reply;
      expandIsland();
    });
    drawerThreadsList.appendChild(el);
  });
}

drawerSearchInput.addEventListener('input', (e) => {
  renderHistoryDrawer(e.target.value);
});

// Render Connected Apps Grid
function renderAppsGrid() {
  appsGrid.innerHTML = '';
  Voice.AIState.connectedApps.forEach(app => {
    const card = document.createElement('div');
    card.className = 'connected-app-card';
    card.innerHTML = `
      <div class="app-icon-large" style="background: ${app.color}">${app.icon}</div>
      <div class="app-card-details">
        <div class="app-card-title">${app.name}</div>
        <div class="app-card-desc">${app.desc}</div>
      </div>
      <div class="toggle-switch ${app.enabled ? 'on' : ''}" data-id="${app.id}">
        <div class="toggle-knob"></div>
      </div>
    `;

    const toggle = card.querySelector('.toggle-switch');
    toggle.addEventListener('click', () => {
      app.enabled = !app.enabled;
      toggle.classList.toggle('on');
      showToast(`${app.name} integration ${app.enabled ? 'enabled' : 'disabled'}`);
    });

    appsGrid.appendChild(card);
  });
}

// App Builder Modal
document.getElementById('openAppBuilderBtn').addEventListener('click', () => {
  modalOverlay.classList.add('open');
});

document.getElementById('modalCloseBtn').addEventListener('click', () => {
  modalOverlay.classList.remove('open');
});

document.getElementById('generateAppBtn').addEventListener('click', () => {
  const btn = document.getElementById('generateAppBtn');
  btn.textContent = 'Building integration...';
  btn.disabled = true;

  setTimeout(() => {
    btn.textContent = 'Generate';
    btn.disabled = false;
    modalOverlay.classList.remove('open');

    Voice.AIState.connectedApps.unshift({
      id: `custom_${Date.now()}`,
      name: "Things 3 Custom MCP",
      desc: "Custom inbox task adder built via voice prompt.",
      icon: "🛠",
      color: "#007AFF",
      enabled: true
    });

    renderAppsGrid();
    showToast('New MCP integration generated and ready!');
  }, 1200);
});

// Global Hotkeys
window.addEventListener('keydown', (e) => {
  // Cmd+Shift+C or 'c' alone when not in input: Trigger Circle to Ask
  if (((e.metaKey || e.ctrlKey) && e.shiftKey && e.key.toLowerCase() === 'c') ||
      (e.key.toLowerCase() === 'c' && document.activeElement !== islandInput && !Voice.AIState.isScreenCaptureActive)) {
    e.preventDefault();
    triggerCircleToAsk();
  }
  // Cmd+D for Dictation
  if (e.key === 'd' && (e.metaKey || e.ctrlKey)) {
    e.preventDefault();
    startVoiceInput('Dictation Mode');
  }
  // Cmd+A for Agent
  if (e.key === 'a' && (e.metaKey || e.ctrlKey)) {
    e.preventDefault();
    startVoiceInput('Agent Mode');
  }
  // Escape cancels selection or collapses unpinned island
  if (e.key === 'Escape') {
    if (Voice.AIState.isScreenCaptureActive) {
      closeCircleToAsk();
    } else {
      modalOverlay.classList.remove('open');
      collapseIsland(true);
    }
  }
});

// Mode Card Direct Clicks
document.getElementById('dictationModeCard').addEventListener('click', () => {
  startVoiceInput('Dictation Mode');
});

document.getElementById('agentModeCard').addEventListener('click', () => {
  startVoiceInput('Agent Mode');
});

// Render Connector Registry
function renderConnectorsList() {
  if (!connectorsList) return;
  connectorsList.innerHTML = '';
  VerifiedConnectors.forEach(c => {
    const item = document.createElement('div');
    item.className = 'connected-app-card';
    item.style.alignItems = 'center';
    item.innerHTML = `
      <div class="app-icon-large" style="background: ${c.color}; font-size: 16px;">${c.icon}</div>
      <div class="app-card-details">
        <div style="display: flex; align-items: center; gap: 8px;">
          <span class="app-card-title">${c.name}</span>
          <span style="font-size: 9px; font-weight: bold; background: rgba(52, 199, 89, 0.15); color: #34c759; padding: 2px 6px; border-radius: 4px;">Verified</span>
          <span style="font-size: 11px; color: #888;">${c.method}</span>
        </div>
        <div style="display: flex; gap: 4px; margin-top: 4px; flex-wrap: wrap;">
          ${c.actions.map(act => `<span style="font-size: 10px; background: rgba(0,0,0,0.05); padding: 1px 6px; border-radius: 3px; font-family: monospace;">${act}</span>`).join('')}
        </div>
      </div>
      <button style="background: none; border: 1px solid #ddd; border-radius: 9999px; padding: 4px 12px; font-size: 11px; font-weight: 600; cursor: pointer;">Ready</button>
    `;
    connectorsList.appendChild(item);
  });
}

// Render Remembered Permissions Table
function renderPermissionsTable() {
  if (!permissionsTable) return;
  permissionsTable.innerHTML = '';
  RememberedGrants.forEach(g => {
    const row = document.createElement('div');
    row.style.cssText = "display: flex; justify-content: space-between; align-items: center; padding: 8px 10px; background: rgba(0,0,0,0.02); border: 1px solid rgba(0,0,0,0.06); border-radius: 6px; font-size: 12px;";
    row.innerHTML = `
      <div>
        <span style="font-weight: 600;">${g.app}</span>
        <span style="color: #666; margin-left: 6px;">scope: ${g.capability}</span>
        <span style="font-size: 10px; background: rgba(0,113,227,0.1); color: #0071e3; padding: 1px 5px; border-radius: 3px; margin-left: 6px;">${g.expiry}</span>
      </div>
      <button class="btn-revoke-grant" data-id="${g.id}" style="background: none; border: 1px solid #ff453a; color: #ff453a; border-radius: 9999px; padding: 2px 8px; font-size: 10px; font-weight: 600; cursor: pointer;">Revoke</button>
    `;
    const revokeBtn = row.querySelector('.btn-revoke-grant');
    revokeBtn.addEventListener('click', () => {
      RememberedGrants = RememberedGrants.filter(item => item.id !== g.id);
      renderPermissionsTable();
      showToast(`${g.app} permission grant revoked`);
    });
    permissionsTable.appendChild(row);
  });
}

// Subtab Toggles in Apps
const tabMarketplace = document.getElementById('tabMarketplace');
const tabMcpServer = document.getElementById('tabMcpServer');
const sectionMarketplace = document.getElementById('sectionMarketplace');
const sectionMcpServer = document.getElementById('sectionMcpServer');

function switchAppSubtab(targetTab, targetSection) {
  [tabMyApps, tabConnectors, tabMarketplace, tabMcpServer].forEach(t => t && t.classList.remove('active'));
  [sectionMyApps, sectionConnectors, sectionMarketplace, sectionMcpServer].forEach(s => s && (s.style.display = 'none'));
  
  if (targetTab) targetTab.classList.add('active');
  if (targetSection) targetSection.style.display = (targetSection === sectionConnectors || targetSection === sectionMarketplace || targetSection === sectionMcpServer) ? 'flex' : 'block';
}

if (tabMyApps) tabMyApps.addEventListener('click', () => switchAppSubtab(tabMyApps, sectionMyApps));
if (tabConnectors) tabConnectors.addEventListener('click', () => switchAppSubtab(tabConnectors, sectionConnectors));
if (tabMarketplace) tabMarketplace.addEventListener('click', () => {
  switchAppSubtab(tabMarketplace, sectionMarketplace);
  renderMarketplaceGrid();
});
if (tabMcpServer) tabMcpServer.addEventListener('click', () => switchAppSubtab(tabMcpServer, sectionMcpServer));

// Platform Switcher (macOS vs Windows 11)
let currentPlatform = 'macos';
const btnPlatformMac = document.getElementById('btnPlatformMac');
const btnPlatformWin = document.getElementById('btnPlatformWin');

if (btnPlatformMac && btnPlatformWin) {
  btnPlatformMac.addEventListener('click', () => {
    currentPlatform = 'macos';
    btnPlatformMac.style.background = '#ffffff';
    btnPlatformMac.style.color = '#000000';
    btnPlatformMac.style.fontWeight = 'bold';
    btnPlatformWin.style.background = 'none';
    btnPlatformWin.style.color = '#555';
    btnPlatformWin.style.fontWeight = '500';

    // macOS specific styling
    document.querySelectorAll('.keycap').forEach(k => {
      if (k.textContent.includes('Win')) k.textContent = 'fn';
    });
    notchIsland.style.top = '0';
    notchIsland.style.borderRadius = '0 0 18px 18px';
    showToast("Switched to macOS Tahoe Mode (Hardware Notch & Liquid Glass)");
  });

  btnPlatformWin.addEventListener('click', () => {
    currentPlatform = 'windows';
    btnPlatformWin.style.background = '#0078d4';
    btnPlatformWin.style.color = '#ffffff';
    btnPlatformWin.style.fontWeight = 'bold';
    btnPlatformMac.style.background = 'none';
    btnPlatformMac.style.color = '#555';
    btnPlatformMac.style.fontWeight = '500';

    // Windows 11 specific styling
    document.querySelectorAll('.keycap').forEach(k => {
      if (k.textContent === 'fn') k.textContent = 'Win + H';
    });
    // Windows has no hardware notch: top island becomes flush pill
    notchIsland.style.top = '6px';
    notchIsland.style.borderRadius = '9999px';
    showToast("Switched to Windows 11 Mode (Mica material, Win+H hotkey, Taskbar Tray)");
  });
}

// Initial Render
renderHistoryDrawer();
renderAppsGrid();
renderConnectorsList();
renderPermissionsTable();
setIslandState('idle');

// ==========================================================================
// Milestone 2: 100+ Multilingual Dictation, Polish Engine, and Localizer
// ==========================================================================

const DictationFixtures = [
  { code: 'en', flag: '🇺🇸', name: 'English', text: 'Um, like actually, I was thinking we should try wako ai for voice os today.', isRTL: false },
  { code: 'hi', flag: '🇮🇳', name: 'Hindi', text: 'नमस्ते, क्या आप आज शाम की मीटिंग का समय बदल सकते हैं?', isRTL: false },
  { code: 'hinglish', flag: '🇮🇳', name: 'Hinglish (Code-Switch)', text: 'Spotify pe meri chill playlist laga do aur Slack pe team ko update kar do.', isRTL: false, isCodeSwitch: true },
  { code: 'ja', flag: '🇯🇵', name: 'Japanese', text: 'こんにちは、明日のプロジェクトキックオフミーティングの議題を共有します。', isRTL: false },
  { code: 'ar', flag: '🇸🇦', name: 'Arabic (RTL)', text: 'مرحبا بك، يرجى مراجعة التقرير المالي قبل نهاية اليوم.', isRTL: true },
  { code: 'es', flag: '🇪🇸', name: 'Spanish', text: 'Hola equipo, por favor revisen la propuesta antes de la reunión de hoy.', isRTL: false },
  { code: 'fr', flag: '🇫🇷', name: 'French', text: 'Bonjour à tous, voici le compte-rendu de notre discussion technique.', isRTL: false },
  { code: 'de', flag: '🇩🇪', name: 'German', text: 'Guten Morgen, bitte prüfen Sie die Dokumentation und das Design.', isRTL: false },
  { code: 'pt', flag: '🇧🇷', name: 'Portuguese', text: 'Olá pessoal, compartilhei o link com a gravação da apresentação.', isRTL: false },
  { code: 'zh', flag: '🇨🇳', name: 'Mandarin', text: '您好，请查看今天上午更新的产品设计规范和代码库。', isRTL: false },
  { code: 'ko', flag: '🇰🇷', name: 'Korean', text: '안녕하세요, 오늘 오후에 예정된 스프린트 회고 회의 링크입니다.', isRTL: false },
  { code: 'ru', flag: '🇷🇺', name: 'Russian', text: 'Привет, команда! Пожалуйста, протестируйте новый релиз приложения.', isRTL: false },
  { code: 'it', flag: '🇮🇹', name: 'Italian', text: 'Ciao a tutti, vi invio la bozza della nuova landing page.', isRTL: false },
  { code: 'nl', flag: '🇳🇱', name: 'Dutch', text: 'Hallo allemaal, hier is de update over de nieuwe release van vandaag.', isRTL: false },
  { code: 'tr', flag: '🇹🇷', name: 'Turkish', text: 'Merhaba, lütfen en son güncelleme notlarını kontrol edin.', isRTL: false }
];

let activeProfile = 'general';
let currentDictationText = '';
let currentRawText = '';
let isSimulatingRecording = false;

// Initialize Fixture Chips
function renderFixtureChips() {
  const container = document.getElementById('fixtureChipsContainer');
  if (!container) return;
  container.innerHTML = '';

  DictationFixtures.forEach((f, idx) => {
    const chip = document.createElement('button');
    chip.className = `fixture-chip ${idx === 0 ? 'active' : ''}`;
    chip.innerHTML = `<span>${f.flag}</span> <span>${f.name}</span>`;
    chip.addEventListener('click', () => {
      document.querySelectorAll('.fixture-chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      applyDictationFixture(f);
    });
    container.appendChild(chip);
  });
}

// App Profile Switcher
document.querySelectorAll('.profile-pill-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.profile-pill-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    activeProfile = btn.dataset.profile;
    repolishCurrentText();
  });
});

// Polish Engine in JS (mirrors DictationPolishEngine.swift)
function polishText(raw, profile) {
  let text = raw;
  const tags = [];

  // 1. Remove filler words
  const fillers = ['um', 'uh', 'you know', 'like actually', 'literally', 'matlab', 'arre'];
  fillers.forEach(filler => {
    const reg = new RegExp(`\\b${filler}\\b,?\\s*`, 'gi');
    if (reg.test(text)) {
      text = text.replace(reg, '');
      tags.push({ type: 'filler', text: `Removed filler: "${filler}"` });
    }
  });

  // 2. Apply phonetic hints
  const hints = {
    'wako ai': 'WakoAI',
    'voice os': 'Voice.AI',
    'vs code': 'VS Code',
    'github': 'GitHub'
  };
  for (const [pattern, repl] of Object.entries(hints)) {
    const reg = new RegExp(`\\b${pattern}\\b`, 'gi');
    if (reg.test(text)) {
      text = text.replace(reg, repl);
      tags.push({ type: 'phonetic', text: `Phonetic hint: "${pattern}" → ${repl}` });
    }
  }

  // 3. Per-App Context Styling
  if (profile === 'slack') {
    if (text.endsWith('.')) {
      text = text.slice(0, -1);
      tags.push({ type: 'style', text: 'Slack style: stripped trailing period' });
    }
  } else if (profile === 'email') {
    if (text.length > 0) {
      text = text.charAt(0).toUpperCase() + text.slice(1);
    }
    if (!/[.!?]$/.test(text)) {
      text += '.';
      tags.push({ type: 'style', text: 'Mail style: added period & capitalized' });
    }
  } else if (profile === 'vscode') {
    if (/^camel case /i.test(text)) {
      const parts = text.replace(/^camel case /i, '').trim().split(/\s+/);
      text = parts[0].toLowerCase() + parts.slice(1).map(w => w.charAt(0).toUpperCase() + w.slice(1)).join('');
      tags.push({ type: 'style', text: 'VS Code: formatted as camelCase' });
    }
  } else if (profile === 'issueTracker') {
    if (text.includes(' aur ') || text.includes(' and ')) {
      const items = text.split(/\s+(?:and|aur)\s+/i);
      text = items.map(i => `- ${i.trim().charAt(0).toUpperCase() + i.trim().slice(1)}`).join('\n');
      tags.push({ type: 'style', text: 'Linear style: bullet list conversion' });
    }
  }

  return { polished: text.trim(), tags };
}

function applyDictationFixture(fixture) {
  currentRawText = fixture.text;
  const rawView = document.getElementById('rawTranscriptView');
  const polishedView = document.getElementById('polishedTranscriptView');
  const detectedBadge = document.getElementById('detectedLangBadge');
  const codeSwitchBadge = document.getElementById('codeSwitchingBadge');
  const rawWordCount = document.getElementById('rawWordCount');

  if (rawView) {
    rawView.textContent = fixture.text;
    rawView.dir = fixture.isRTL ? 'rtl' : 'ltr';
    rawWordCount.textContent = `${fixture.text.trim().split(/\s+/).length} words`;
  }

  if (detectedBadge) {
    detectedBadge.textContent = `${fixture.flag} ${fixture.name} · 99%`;
  }

  if (codeSwitchBadge) {
    codeSwitchBadge.style.display = fixture.isCodeSwitch ? 'inline' : 'none';
  }

  repolishCurrentText(fixture.isRTL);
}

function repolishCurrentText(isRTL = false) {
  if (!currentRawText) return;
  const polishedView = document.getElementById('polishedTranscriptView');
  const tagsWrap = document.getElementById('correctionTagsWrap');
  const cleanWordCount = document.getElementById('cleanWordCount');

  const { polished, tags } = polishText(currentRawText, activeProfile);
  currentDictationText = polished;

  if (polishedView) {
    polishedView.textContent = polished;
    polishedView.dir = isRTL ? 'rtl' : 'ltr';
    cleanWordCount.textContent = `${polished.split(/\s+/).length} words`;
  }

  if (tagsWrap) {
    tagsWrap.innerHTML = '';
    tags.forEach(t => {
      const span = document.createElement('span');
      span.className = 'correction-tag';
      span.textContent = t.text;
      tagsWrap.appendChild(span);
    });
  }
}

// Spoken Edit Mode Commands
document.querySelectorAll('.spoken-cmd-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    const cmd = btn.dataset.cmd;
    const polishedView = document.getElementById('polishedTranscriptView');
    let text = polishedView ? polishedView.textContent : '';

    if (cmd === 'make it bullet points') {
      const lines = text.split('\n').filter(l => l.trim().length > 0);
      text = lines.map(l => l.startsWith('- ') ? l : `- ${l}`).join('\n');
      showToast('Spoken command: Formatted as bulleted list');
    } else if (cmd === 'more casual') {
      text = text.replace(/do not/gi, "don't").replace(/i am/gi, "I'm").replace(/cannot/gi, "can't");
      if (text.endsWith('.')) text = text.slice(0, -1);
      showToast('Spoken command: Made tone casual');
    } else if (cmd === 'more formal') {
      text = text.replace(/don't/gi, "do not").replace(/can't/gi, "cannot");
      if (!text.endsWith('.')) text += '.';
      showToast('Spoken command: Made tone formal');
    } else if (cmd === 'wrap in code block') {
      text = `\`\`\`\n${text}\n\`\`\``;
      showToast('Spoken command: Wrapped in code block');
    } else if (cmd === 'translate to japanese') {
      text = 'こんにちは、明日のプロジェクトキックオフミーティングの議題を共有します。';
      showToast('Spoken command: Translated to Japanese');
    } else if (cmd === 'shorten') {
      const sentences = text.split('. ');
      text = sentences.slice(0, 1).join('. ') + '.';
      showToast('Spoken command: Shortened text');
    }

    if (polishedView) {
      polishedView.textContent = text;
    }
  });
});

// UI Localization Catalog (English & Japanese)
const AppLocalizations = {
  en: {
    dashboard: 'Dashboard',
    dictation: 'Dictation',
    agent: 'Agent',
    apps: 'Apps',
    settings: 'Settings',
    dictationTitle: '100+ Multilingual Dictation Studio'
  },
  ja: {
    dashboard: 'ダッシュボード',
    dictation: 'ディクテーション',
    agent: 'エージェント',
    apps: 'アプリ連携',
    settings: '環境設定',
    dictationTitle: '100以上の言語に対応したディクテーションスタジオ'
  }
};

const uiLangSelect = document.getElementById('uiLangSelect');
if (uiLangSelect) {
  uiLangSelect.addEventListener('change', (e) => {
    const lang = e.target.value;
    const strings = AppLocalizations[lang] || AppLocalizations.en;
    const titleEl = document.getElementById('dictationHeadingTitle');
    if (titleEl) titleEl.textContent = strings.dictationTitle;

    document.querySelectorAll('.nav-item').forEach(item => {
      const tab = item.dataset.tab;
      if (strings[tab]) {
        const span = item.querySelector('span:last-child');
        if (span) span.textContent = strings[tab];
      }
    });
    showToast(`UI Localized to ${lang === 'ja' ? '日本語' : 'English'}`);
  });
}

// Waveform Animation Loop
function startWaveformCanvas() {
  const canvas = document.getElementById('dictationWaveformCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  let step = 0;

  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const width = canvas.width;
    const height = canvas.height;
    const midY = height / 2;

    ctx.lineWidth = 2;
    ctx.strokeStyle = isSimulatingRecording ? '#34c759' : '#007aff';
    ctx.beginPath();

    const bars = 40;
    const barWidth = width / bars;

    for (let i = 0; i < bars; i++) {
      const x = i * barWidth + barWidth / 2;
      const amp = isSimulatingRecording ? Math.sin((step + i) * 0.4) * 14 + Math.random() * 8 : Math.sin((step + i) * 0.15) * 5 + 3;
      ctx.moveTo(x, midY - amp);
      ctx.lineTo(x, midY + amp);
    }
    ctx.stroke();

    step += 0.5;
    requestAnimationFrame(draw);
  }
  draw();
}

// Dictation Mic Simulation Toggle
const btnDictationSimMic = document.getElementById('btnDictationSimMic');
if (btnDictationSimMic) {
  btnDictationSimMic.addEventListener('click', () => {
    isSimulatingRecording = !isSimulatingRecording;
    btnDictationSimMic.style.background = isSimulatingRecording ? '#ff3b30' : '#007aff';
    const status = document.getElementById('waveformStatus');
    if (status) {
      status.textContent = isSimulatingRecording ? '🔴 Listening (Speech Active)...' : 'Live Audio Input Simulator';
    }
    showToast(isSimulatingRecording ? 'Dictation started · Speak in any language' : 'Dictation stopped · Cleaned & formatted');
  });
}

// Run initial setup for Dictation Studio
renderFixtureChips();
startWaveformCanvas();
if (DictationFixtures.length > 0) {
  applyDictationFixture(DictationFixtures[0]);
}

// ==========================================================================
// Milestone 3: App Store Marketplace (10 Manifests) & Custom MCP Handshake
// ==========================================================================

const MarketplaceManifests = [
  {
    id: "linear",
    name: "Linear",
    publisher: "Linear Orbit, Inc.",
    version: "2.4.0",
    icon: "📐",
    categories: ["Productivity", "Developer"],
    authType: "oauth2",
    summary: "Create issues, update project cycles, and assign tasks via voice.",
    permissionsRequired: [
      { scope: "read:issues", justification: "View assigned and team sprint tasks" },
      { scope: "write:issues", justification: "Create and update issues from spoken requests" }
    ],
    actions: [
      { id: "create_issue", name: "Create Issue", riskLevel: "Reversible" },
      { id: "list_my_issues", name: "List My Issues", riskLevel: "Read-Only" }
    ],
    deepLinkTemplate: "https://linear.app/issue/{id}",
    verificationBadge: "Verified by Voice.AI",
    platformSupport: ["macOS", "Windows", "Web"]
  },
  {
    id: "spotify",
    name: "Spotify",
    publisher: "Spotify AB",
    version: "1.8.2",
    icon: "🎵",
    categories: ["Music & Media"],
    authType: "oauth2",
    summary: "Play songs, search playlists, and control audio playback in background.",
    permissionsRequired: [
      { scope: "user-modify-playback-state", justification: "Change tracks and resume playback" },
      { scope: "user-read-playback-state", justification: "Read currently playing track title" }
    ],
    actions: [
      { id: "play_playlist", name: "Play Playlist", riskLevel: "Reversible" }
    ],
    deepLinkTemplate: "spotify:playlist/{id}",
    verificationBadge: "Verified by Voice.AI",
    platformSupport: ["macOS", "Windows", "Web"]
  },
  {
    id: "slack",
    name: "Slack",
    publisher: "Slack Technologies",
    version: "4.1.0",
    icon: "💬",
    categories: ["Communication"],
    authType: "oauth2",
    summary: "Post status messages, notify channels, and read unread mentions.",
    permissionsRequired: [
      { scope: "chat:write", justification: "Send message to specified channel" },
      { scope: "channels:history", justification: "Check recent mentions" }
    ],
    actions: [
      { id: "send_message", name: "Send Message", riskLevel: "Consequential" }
    ],
    deepLinkTemplate: "slack://channel?team={team}&id={channel}",
    verificationBadge: "Verified by Voice.AI",
    platformSupport: ["macOS", "Windows", "Web"]
  },
  {
    id: "github",
    name: "GitHub",
    publisher: "GitHub, Inc.",
    version: "3.2.1",
    icon: "🐙",
    categories: ["Developer"],
    authType: "oauth2",
    summary: "Inspect pull requests, review workflow runs, and check open notifications.",
    permissionsRequired: [
      { scope: "repo:read", justification: "Fetch open pull requests and issues" }
    ],
    actions: [
      { id: "list_prs", name: "List Pull Requests", riskLevel: "Read-Only" }
    ],
    deepLinkTemplate: "https://github.com/{repo}/pull/{pr}",
    verificationBadge: "Verified by Voice.AI",
    platformSupport: ["macOS", "Windows", "Web"]
  },
  {
    id: "notion",
    name: "Notion",
    publisher: "Notion Labs",
    version: "2.1.0",
    icon: "📓",
    categories: ["Productivity", "Notes & Knowledge"],
    authType: "oauth2",
    summary: "Create pages, capture quick notes into databases, and query workspace blocks.",
    permissionsRequired: [
      { scope: "pages:create", justification: "Add newly transcribed notes to target database" }
    ],
    actions: [
      { id: "append_note", name: "Append Note", riskLevel: "Reversible" }
    ],
    deepLinkTemplate: "https://notion.so/{pageId}",
    verificationBadge: "Verified by Voice.AI",
    platformSupport: ["macOS", "Windows", "Web"]
  },
  {
    id: "youtube",
    name: "YouTube Studio",
    publisher: "Google LLC",
    version: "1.5.0",
    icon: "▶",
    categories: ["Music & Media"],
    authType: "oauth2",
    summary: "Look up video analytics, subscriber growth, and channel comments.",
    permissionsRequired: [
      { scope: "youtube.readonly", justification: "Read channel view stats and subscriber counts" }
    ],
    actions: [
      { id: "get_stats", name: "Get Channel Stats", riskLevel: "Read-Only" }
    ],
    deepLinkTemplate: "https://studio.youtube.com/channel/{channelId}",
    verificationBadge: "Verified by Voice.AI",
    platformSupport: ["macOS", "Windows", "Web"]
  },
  {
    id: "vscode",
    name: "VS Code",
    publisher: "Microsoft",
    version: "1.92.0",
    icon: "💻",
    categories: ["Developer"],
    authType: "app_intent",
    summary: "Open files, run workspace tasks, and jump to definition without mouse navigation.",
    permissionsRequired: [
      { scope: "local:cli", justification: "Execute code binary commands in active project" }
    ],
    actions: [
      { id: "open_file", name: "Open File", riskLevel: "Read-Only" }
    ],
    deepLinkTemplate: "vscode://file/{path}:{line}",
    verificationBadge: "Verified by Voice.AI",
    platformSupport: ["macOS", "Windows"]
  },
  {
    id: "jira",
    name: "Jira Software",
    publisher: "Atlassian",
    version: "3.0.0",
    icon: "🔷",
    categories: ["Productivity", "Developer"],
    authType: "oauth2",
    summary: "Log sprint story points, transition tickets, and comment on bug reports.",
    permissionsRequired: [
      { scope: "read:jira-work", justification: "Inspect assigned sprint tickets" }
    ],
    actions: [
      { id: "transition_ticket", name: "Transition Ticket", riskLevel: "Consequential" }
    ],
    deepLinkTemplate: "https://atlassian.net/browse/{key}",
    verificationBadge: "Verified by Voice.AI",
    platformSupport: ["macOS", "Windows", "Web"]
  },
  {
    id: "discord",
    name: "Discord",
    publisher: "Discord Inc.",
    version: "2.1.4",
    icon: "🎮",
    categories: ["Communication"],
    authType: "oauth2",
    summary: "Send voice-to-text messages to gaming guild channels and listen to soundboards.",
    permissionsRequired: [
      { scope: "messages.write", justification: "Send message to authorized channel" }
    ],
    actions: [
      { id: "post_message", name: "Post Message", riskLevel: "Consequential" }
    ],
    deepLinkTemplate: "discord://discord.com/channels/{guild}/{channel}",
    verificationBadge: "Verified by Voice.AI",
    platformSupport: ["macOS", "Windows", "Web"]
  },
  {
    id: "gmail",
    name: "Google Gmail",
    publisher: "Google LLC",
    version: "2.8.0",
    icon: "✉️",
    categories: ["Communication", "Productivity"],
    authType: "oauth2",
    summary: "Draft emails, search message threads, and reply politely with AI summaries.",
    permissionsRequired: [
      { scope: "gmail.compose", justification: "Create email drafts for user review" }
    ],
    actions: [
      { id: "create_draft", name: "Create Draft", riskLevel: "Reversible" }
    ],
    deepLinkTemplate: "https://mail.google.com/mail/u/0/#inbox/{threadId}",
    verificationBadge: "Verified by Voice.AI",
    platformSupport: ["macOS", "Windows", "Web"]
  }
];

const installedManifestIds = new Set(["spotify", "slack", "things", "yt"]);
let activeMarketCategory = 'all';
let marketSearchTerm = '';
let pendingInstallManifest = null;

function renderMarketplaceGrid() {
  const grid = document.getElementById('marketplaceGrid');
  if (!grid) return;
  grid.innerHTML = '';

  const filtered = MarketplaceManifests.filter(m => {
    if (activeMarketCategory !== 'all' && !m.categories.includes(activeMarketCategory)) return false;
    if (marketSearchTerm) {
      const q = marketSearchTerm.toLowerCase();
      if (!m.name.toLowerCase().includes(q) && !m.summary.toLowerCase().includes(q) && !m.publisher.toLowerCase().includes(q)) {
        return false;
      }
    }
    return true;
  });

  filtered.forEach(manifest => {
    const isInstalled = installedManifestIds.has(manifest.id);
    const card = document.createElement('div');
    card.className = 'marketplace-card';

    const isCustomMcp = manifest.verificationBadge === "Custom MCP";
    const badgeHtml = isCustomMcp
      ? `<span class="badge-custom-mcp-chip">🔌 Custom MCP</span>`
      : `<span class="badge-verified-voice.ai">✓ Verified</span>`;

    card.innerHTML = `
      <div>
        <div class="market-card-top">
          <div class="market-icon-box">${manifest.icon}</div>
          <div class="market-meta">
            <div class="market-title-row">
              <span class="market-app-name">${manifest.name}</span>
              ${badgeHtml}
            </div>
            <div class="market-publisher">${manifest.publisher} · v${manifest.version}</div>
          </div>
        </div>
        <p class="market-summary">${manifest.summary}</p>
      </div>
      <div class="market-card-bottom">
        <span class="market-platforms-pill">${manifest.platformSupport.join(' · ')}</span>
        <button class="btn-market-install ${isInstalled ? 'installed' : ''}" data-id="${manifest.id}">
          ${isInstalled ? 'Uninstall' : 'Install'}
        </button>
      </div>
    `;

    const btn = card.querySelector('.btn-market-install');
    btn.addEventListener('click', () => {
      if (installedManifestIds.has(manifest.id)) {
        installedManifestIds.delete(manifest.id);
        showToast(`Uninstalled ${manifest.name}`);
        renderMarketplaceGrid();
      } else {
        openPermissionsReviewModal(manifest);
      }
    });

    grid.appendChild(card);
  });
}

// Category filter pills
document.querySelectorAll('.market-cat-pill').forEach(pill => {
  pill.addEventListener('click', () => {
    document.querySelectorAll('.market-cat-pill').forEach(p => p.classList.remove('active'));
    pill.classList.add('active');
    activeMarketCategory = pill.dataset.cat;
    renderMarketplaceGrid();
  });
});

// Search input
const marketSearchInput = document.getElementById('marketplaceSearchInput');
if (marketSearchInput) {
  marketSearchInput.addEventListener('input', (e) => {
    marketSearchTerm = e.target.value.trim();
    renderMarketplaceGrid();
  });
}

// Permissions Review Modal
const permReviewModalOverlay = document.getElementById('permReviewModalOverlay');
const permReviewCloseBtn = document.getElementById('permReviewCloseBtn');
const permCancelBtn = document.getElementById('permCancelBtn');
const permConfirmInstallBtn = document.getElementById('permConfirmInstallBtn');

function openPermissionsReviewModal(manifest) {
  pendingInstallManifest = manifest;
  const title = document.getElementById('permModalTitle');
  const pub = document.getElementById('permModalPublisher');
  const icon = document.getElementById('permModalIcon');
  const list = document.getElementById('permScopesList');

  if (title) title.textContent = `Install ${manifest.name}`;
  if (pub) pub.textContent = `${manifest.publisher} · v${manifest.version}`;
  if (icon) icon.textContent = manifest.icon;

  if (list) {
    list.innerHTML = '';
    manifest.permissionsRequired.forEach(p => {
      const row = document.createElement('div');
      row.className = 'scope-item-row';
      row.innerHTML = `
        <span class="scope-title">🔑 ${p.scope}</span>
        <span class="scope-justification">${p.justification}</span>
      `;
      list.appendChild(row);
    });
  }

  if (permReviewModalOverlay) permReviewModalOverlay.classList.add('open');
}

function closePermissionsReviewModal() {
  pendingInstallManifest = null;
  if (permReviewModalOverlay) permReviewModalOverlay.classList.remove('open');
}

if (permReviewCloseBtn) permReviewCloseBtn.addEventListener('click', closePermissionsReviewModal);
if (permCancelBtn) permCancelBtn.addEventListener('click', closePermissionsReviewModal);

if (permConfirmInstallBtn) {
  permConfirmInstallBtn.addEventListener('click', () => {
    if (pendingInstallManifest) {
      installedManifestIds.add(pendingInstallManifest.id);
      showToast(`Installed & Connected: ${pendingInstallManifest.name}`);
      closePermissionsReviewModal();
      renderMarketplaceGrid();
    }
  });
}

// Custom MCP Handshake & Introspection Flow
const btnIntrospectMcp = document.getElementById('btnIntrospectMcp');
const mcpEndpointInput = document.getElementById('mcpEndpointInput');
const mcpIntrospectionResult = document.getElementById('mcpIntrospectionResult');

if (btnIntrospectMcp) {
  btnIntrospectMcp.addEventListener('click', () => {
    const rawVal = mcpEndpointInput ? mcpEndpointInput.value.trim() : '';
    const match = rawVal.match(/(https?:\/\/[^\s]+)/i);
    const urlStr = match ? match[1] : (rawVal || 'http://localhost:8000/sse');

    showToast("Connecting to MCP SSE endpoint & listing tools...");

    setTimeout(() => {
      // Mock MCP handshake response
      const discoveredTools = [
        { name: "query_database", desc: "Execute read-only SQL queries against connected DB", risk: "Read-Only" },
        { name: "insert_record", desc: "Insert verified record into telemetry database", risk: "Consequential" }
      ];

      if (mcpIntrospectionResult) {
        mcpIntrospectionResult.style.display = 'flex';
        mcpIntrospectionResult.innerHTML = `
          <div class="mode-card" style="border-color: #af52de;">
            <div style="display: flex; justify-content: space-between; align-items: center;">
              <span style="font-weight: 600; color: #af52de;">✓ MCP Handshake Succeeded (Protocol v1.0)</span>
              <span class="badge-custom-mcp-chip">2 Tools Introspected</span>
            </div>
            <p style="font-size: 12px; color: #666; margin-top: 4px;">Server: <code>${urlStr}</code></p>
            <div style="display: flex; flex-direction: column; gap: 6px; margin: 8px 0;">
              ${discoveredTools.map(t => `
                <div style="background: #f2f2f7; padding: 6px 10px; border-radius: 6px; font-size: 12px;">
                  <b>${t.name}</b>: ${t.desc} <span style="font-size: 10px; color: #888;">(${t.risk})</span>
                </div>
              `).join('')}
            </div>
            <button class="btn-generate" id="btnRegisterDynamicMcp" style="background: #af52de; align-self: flex-start; margin-top: 6px;">
              Register into My Integrations
            </button>
          </div>
        `;

        const btnRegister = document.getElementById('btnRegisterDynamicMcp');
        if (btnRegister) {
          btnRegister.addEventListener('click', () => {
            const dynamicMcp = {
              id: "mcp_" + Date.now(),
              name: `Custom MCP (${urlStr.replace(/^https?:\/\//, '').split('/')[0]})`,
              publisher: "User MCP Server",
              version: "1.0.0",
              icon: "🔌",
              categories: ["AI", "Developer"],
              authType: "mcp",
              summary: `Dynamically connected Model Context Protocol server at ${urlStr}`,
              permissionsRequired: [
                { scope: "network:connect", justification: `Allow Voice.AI to call tools at ${urlStr}` }
              ],
              actions: discoveredTools.map(t => ({ id: t.name, name: t.name, riskLevel: t.risk })),
              deepLinkTemplate: urlStr,
              verificationBadge: "Custom MCP",
              platformSupport: ["macOS", "Windows", "Web"]
            };

            MarketplaceManifests.unshift(dynamicMcp);
            installedManifestIds.add(dynamicMcp.id);
            showToast(`Custom MCP Registered & Activated: ${dynamicMcp.name}`);
            switchAppSubtab(tabMarketplace, sectionMarketplace);
            renderMarketplaceGrid();
          });
        }
      }
    }, 400);
  });
}

// ==========================================================================
// Milestone 5: Task Panel & Persistent Day-Grouped History Engine
// ==========================================================================

const TaskHistoryData = [
  // Today's Active and Completed Tasks
  {
    id: "task_01",
    prompt: "Spotify pe meri chill playlist laga do",
    appName: "Spotify",
    actionName: "play_playlist",
    status: "Running",
    progress: 0.65,
    elapsedSeconds: 0.8,
    deepLinkURL: "spotify:playlist:chill",
    day: "Today",
    timeStr: "12:04 PM"
  },
  {
    id: "task_02",
    prompt: "Linear pe new issue banao: Fix audio drift",
    appName: "Linear",
    actionName: "create_issue",
    status: "Running",
    progress: 0.40,
    elapsedSeconds: 0.5,
    deepLinkURL: "https://linear.app/issue/ENG-402",
    day: "Today",
    timeStr: "12:02 PM"
  },
  {
    id: "task_03",
    prompt: "Slack pe team ko bata do meeting late hai",
    appName: "Slack",
    actionName: "send_message",
    status: "Done",
    progress: 1.0,
    elapsedSeconds: 1.2,
    deepLinkURL: "slack://channel?team=T01&id=C01",
    day: "Today",
    timeStr: "11:45 AM"
  },
  {
    id: "task_04",
    prompt: "GitHub pe open PRs dikhao",
    appName: "GitHub",
    actionName: "list_prs",
    status: "Done",
    progress: 1.0,
    elapsedSeconds: 0.9,
    deepLinkURL: "https://github.com/voice.ai/agent/pulls",
    day: "Today",
    timeStr: "11:20 AM"
  },
  {
    id: "task_05",
    prompt: "Sync files to Google Drive backup",
    appName: "Google Drive",
    actionName: "upload_files",
    status: "Failed",
    progress: 0.3,
    elapsedSeconds: 0.4,
    deepLinkURL: "https://drive.google.com",
    day: "Today",
    timeStr: "10:15 AM",
    errorMessage: "Connection timed out"
  },

  // Yesterday
  {
    id: "task_06",
    prompt: "Apple Notes mein product launch ideas note karo",
    appName: "Apple Notes",
    actionName: "append_note",
    status: "Done",
    progress: 1.0,
    elapsedSeconds: 0.6,
    deepLinkURL: "notes://notes",
    day: "Yesterday",
    timeStr: "5:30 PM"
  },
  {
    id: "task_07",
    prompt: "Jira ticket ENG-99 transition karo to Done",
    appName: "Jira",
    actionName: "transition_status",
    status: "Done",
    progress: 1.0,
    elapsedSeconds: 1.1,
    deepLinkURL: "https://atlassian.net/browse/ENG-99",
    day: "Yesterday",
    timeStr: "3:10 PM"
  },

  // Earlier
  {
    id: "task_08",
    prompt: "Obsidian daily note create karo",
    appName: "Obsidian",
    actionName: "create_note",
    status: "Done",
    progress: 1.0,
    elapsedSeconds: 0.4,
    deepLinkURL: "obsidian://open",
    day: "Earlier",
    timeStr: "Nov 3, 2026"
  }
];

let activeTaskFilter = 'all';
let taskSearchQuery = '';

function renderTaskPanel() {
  const runningList = document.getElementById('runningTasksList');
  const activeCountEl = document.getElementById('activeQueueCount');
  const historyContainer = document.getElementById('dayGroupedHistoryContainer');
  const runningSection = document.getElementById('runningTasksSection');

  if (!runningList || !historyContainer) return;

  // 1. Render Running Tasks
  const runningTasks = TaskHistoryData.filter(t => t.status === 'Running' || t.status === 'Paused');
  if (activeCountEl) {
    activeCountEl.textContent = `${runningTasks.length} Running in Background (No Interruption)`;
  }
  if (runningSection) {
    runningSection.style.display = (runningTasks.length > 0 && (activeTaskFilter === 'all' || activeTaskFilter === 'running')) ? 'flex' : 'none';
  }

  runningList.innerHTML = '';
  runningTasks.forEach(t => {
    const item = document.createElement('div');
    item.className = 'running-task-item';
    item.innerHTML = `
      <div style="display: flex; align-items: center; gap: 10px; flex: 1;">
        <span style="font-size: 16px;">⚡️</span>
        <div>
          <div style="font-size: 13px; font-weight: 600; color: #1d1d1f;">${t.prompt}</div>
          <div style="font-size: 11px; color: #8e8e93;">${t.appName} · ${t.actionName} · ${t.elapsedSeconds}s</div>
        </div>
      </div>
      <div class="task-progress-track">
        <div class="task-progress-fill" style="width: ${Math.round(t.progress * 100)}%;"></div>
      </div>
      <div style="display: flex; gap: 6px;">
        <button class="btn-export btn-pause-task" data-id="${t.id}" style="padding: 3px 8px;">${t.status === 'Paused' ? '▶' : '⏸'}</button>
        <button class="btn-export btn-cancel-task" data-id="${t.id}" style="padding: 3px 8px; color: #ff3b30;">✕</button>
      </div>
    `;

    item.querySelector('.btn-pause-task').addEventListener('click', () => {
      t.status = t.status === 'Paused' ? 'Running' : 'Paused';
      showToast(t.status === 'Paused' ? 'Task paused' : 'Task resumed');
      renderTaskPanel();
    });

    item.querySelector('.btn-cancel-task').addEventListener('click', () => {
      t.status = 'Failed';
      t.errorMessage = 'Cancelled by user mid-flight';
      showToast('Task cancelled mid-flight');
      renderTaskPanel();
    });

    runningList.appendChild(item);
  });

  // 2. Filter & Render Day-Grouped History
  let filtered = TaskHistoryData.filter(t => {
    if (activeTaskFilter === 'running' && t.status !== 'Running' && t.status !== 'Paused') return false;
    if (activeTaskFilter === 'done' && t.status !== 'Done') return false;
    if (activeTaskFilter === 'failed' && t.status !== 'Failed') return false;
    if (taskSearchQuery) {
      const q = taskSearchQuery.toLowerCase();
      const match = t.prompt.toLowerCase().includes(q) || t.appName.toLowerCase().includes(q) || (t.errorMessage && t.errorMessage.toLowerCase().includes(q));
      if (!match) return false;
    }
    return true;
  });

  historyContainer.innerHTML = '';
  const days = ['Today', 'Yesterday', 'Earlier'];

  days.forEach(day => {
    const dayTasks = filtered.filter(t => t.day === day);
    if (dayTasks.length === 0) return;

    const groupHeader = document.createElement('div');
    groupHeader.className = 'day-group-header';
    groupHeader.textContent = day;
    historyContainer.appendChild(groupHeader);

    dayTasks.forEach(task => {
      const card = document.createElement('div');
      card.className = 'history-card-item';

      let statusBadge = '';
      if (task.status === 'Done') {
        statusBadge = `<span class="status-badge-done">✓ Done (${task.elapsedSeconds}s)</span>`;
      } else if (task.status === 'Failed') {
        statusBadge = `<span class="status-badge-failed">✕ Failed</span>`;
      } else {
        statusBadge = `<span class="status-badge-running">⚡️ ${task.status}</span>`;
      }

      const retryBtnHtml = task.status === 'Failed' 
        ? `<button class="btn-retry-task" data-id="${task.id}">↺ Retry</button>` 
        : '';

      const viewBtnHtml = task.deepLinkURL 
        ? `<a href="${task.deepLinkURL}" target="_blank" class="btn-view-deep-link" onclick="event.preventDefault(); showToast('Opened deep link: ${task.deepLinkURL}');">View ↗</a>` 
        : '';

      card.innerHTML = `
        <div class="history-card-meta">
          <div class="history-prompt-text">${task.prompt}</div>
          <div class="history-action-sub">
            <b>${task.appName}</b> · ${task.actionName} · ${task.timeStr}
            ${task.errorMessage ? ` · <span style="color: #ff3b30;">${task.errorMessage}</span>` : ''}
          </div>
        </div>
        <div class="history-right-actions">
          ${statusBadge}
          ${retryBtnHtml}
          ${viewBtnHtml}
        </div>
      `;

      const retryBtn = card.querySelector('.btn-retry-task');
      if (retryBtn) {
        retryBtn.addEventListener('click', () => {
          task.status = 'Running';
          task.progress = 0.2;
          delete task.errorMessage;
          showToast(`Retrying task: "${task.prompt}"`);
          renderTaskPanel();
        });
      }

      historyContainer.appendChild(card);
    });
  });
}

// Filter button clicks
document.querySelectorAll('#taskStatusFilters .market-cat-pill').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#taskStatusFilters .market-cat-pill').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    activeTaskFilter = btn.dataset.filter;
    renderTaskPanel();
  });
});

// Search input
const taskSearchInput = document.getElementById('taskSearchInput');
if (taskSearchInput) {
  taskSearchInput.addEventListener('input', (e) => {
    taskSearchQuery = e.target.value.trim();
    renderTaskPanel();
  });
}

// Export Handlers
const btnExportJson = document.getElementById('btnExportJson');
if (btnExportJson) {
  btnExportJson.addEventListener('click', () => {
    const jsonStr = JSON.stringify(TaskHistoryData, null, 2);
    const blob = new Blob([jsonStr], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'voice.ai_task_history.json';
    a.click();
    showToast('Exported Task History to JSON (Encrypted-at-Rest schema)');
  });
}

const btnExportMd = document.getElementById('btnExportMd');
if (btnExportMd) {
  btnExportMd.addEventListener('click', () => {
    let md = '# Voice.AI Task & Session History\n\n| Day | App | Prompt | Action | Status | Duration |\n| :--- | :--- | :--- | :--- | :--- | :--- |\n';
    TaskHistoryData.forEach(t => {
      md += `| ${t.day} | ${t.appName} | ${t.prompt} | ${t.actionName} | ${t.status} | ${t.elapsedSeconds}s |\n`;
    });
    const blob = new Blob([md], { type: 'text/markdown' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'voice.ai_task_history.md';
    a.click();
    showToast('Exported Task History to Markdown');
  });
}

// Hook tab switch to render task panel
document.querySelectorAll('.nav-item').forEach(item => {
  if (item.dataset.tab === 'history') {
    item.addEventListener('click', renderTaskPanel);
  }
});

// ==========================================================================
// Milestone 6: Hotkey Conflict Resolution & Tap vs Hold 250ms Timing Engine
// ==========================================================================

// 1. One-Click Conflict Fix
const btnApply1ClickFix = document.getElementById('btnApply1ClickFix');
const hotkeyConflictBanner = document.getElementById('hotkeyConflictBanner');

if (btnApply1ClickFix && hotkeyConflictBanner) {
  btnApply1ClickFix.addEventListener('click', () => {
    btnApply1ClickFix.textContent = 'Applied ✓';
    btnApply1ClickFix.style.background = '#34c759';
    btnApply1ClickFix.disabled = true;

    const titleEl = hotkeyConflictBanner.querySelector('.conflict-title');
    if (titleEl) {
      titleEl.innerHTML = `<span>✓</span> <span>macOS System Dictation Resolved (Zero Conflict)</span>`;
      titleEl.style.color = '#34c759';
    }
    hotkeyConflictBanner.style.background = 'rgba(52, 199, 89, 0.08)';
    hotkeyConflictBanner.style.borderColor = 'rgba(52, 199, 89, 0.3)';

    showToast("Applied 1-Click Fix: 'fn fn' double-tap reassigned. Voice.AI holds active.");
  });
}

// 2. Configurable Hotkey Selectors
const selectDictationKey = document.getElementById('selectDictationKey');
const selectAgentKey = document.getElementById('selectAgentKey');

if (selectDictationKey) {
  selectDictationKey.addEventListener('change', (e) => {
    const val = e.target.value;
    const label = e.target.options[e.target.selectedIndex].text;
    
    // Update keycaps in UI
    document.querySelectorAll('.keycap').forEach(k => {
      if (k.textContent === 'fn' || k.textContent.includes('Win')) {
        k.textContent = val === 'win_h' ? 'Win + H' : (val === 'right_cmd' ? 'Right ⌘' : (val === 'ctrl_space' ? '⌃ Space' : 'fn'));
      }
    });

    const testBtn = document.getElementById('btnTestHoldKey');
    if (testBtn) testBtn.textContent = `Press & Hold Test Key (${val === 'win_h' ? 'Win+H' : val})`;

    showToast(`Dictation key rebound to: ${label}`);
  });
}

if (selectAgentKey) {
  selectAgentKey.addEventListener('change', (e) => {
    const label = e.target.options[e.target.selectedIndex].text;
    showToast(`Agent key rebound to: ${label}`);
  });
}

// 3. Interactive Key Tester (250ms threshold)
const btnTestHoldKey = document.getElementById('btnTestHoldKey');
const keyTesterFeedback = document.getElementById('keyTesterFeedback');
let testKeyPressTime = 0;

if (btnTestHoldKey && keyTesterFeedback) {
  const startPress = () => {
    testKeyPressTime = Date.now();
    btnTestHoldKey.style.background = '#ff9500';
    btnTestHoldKey.textContent = 'Recording keypress...';
    keyTesterFeedback.textContent = 'Measuring duration...';
    keyTesterFeedback.style.color = '#ff9500';
  };

  const endPress = () => {
    if (!testKeyPressTime) return;
    const duration = Date.now() - testKeyPressTime;
    testKeyPressTime = 0;
    btnTestHoldKey.style.background = '#007aff';
    const currentKey = selectDictationKey ? selectDictationKey.value : 'fn';
    btnTestHoldKey.textContent = `Press & Hold Test Key (${currentKey})`;

    if (duration < 250) {
      keyTesterFeedback.innerHTML = `<b>Short Tap (${duration}ms)</b> ➜ Passed through to macOS Globe / Emoji Picker (Zero Conflict)`;
      keyTesterFeedback.style.color = '#ff9500';
      showToast(`Short tap (${duration}ms): Passed through to system Emoji/Globe`);
    } else {
      keyTesterFeedback.innerHTML = `<b>Hold (${duration}ms >= 250ms)</b> ➜ Voice.AI Dictation Triggered!`;
      keyTesterFeedback.style.color = '#34c759';
      setIslandState('listening');
      showToast(`Hold detected (${duration}ms): Voice.AI Dictation Active`);
      setTimeout(() => setIslandState('idle'), 1800);
    }
  };

  btnTestHoldKey.addEventListener('mousedown', startPress);
  btnTestHoldKey.addEventListener('mouseup', endPress);
  btnTestHoldKey.addEventListener('touchstart', startPress);
  btnTestHoldKey.addEventListener('touchend', endPress);
}
