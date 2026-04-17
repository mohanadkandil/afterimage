"use strict";
const $ = (id) => document.getElementById(id);
const pending = new Map();
let serial = 0;
function call(action, args = {}) {
  return new Promise((resolve, reject) => {
    const id = String(++serial);
    const timeout = setTimeout(() => {
      pending.delete(id);
      reject(new Error("The app did not respond. Try again."));
    }, 120000);
    pending.set(id, { resolve, reject, timeout });
    if (window.webkit?.messageHandlers?.litt)
      window.webkit.messageHandlers.litt.postMessage({
        id,
        action,
        args,
      });
    else {
      clearTimeout(timeout);
      pending.delete(id);
      reject(
        new Error("Open Litt.app to connect to your local archive."),
      );
    }
  });
}
window.littReceive = ({ id, result, error }) => {
  const p = pending.get(id);
  if (!p) return;
  clearTimeout(p.timeout);
  pending.delete(id);
  error ? p.reject(new Error(error)) : p.resolve(result);
};
let frames = [],
  state = null,
  current = null,
  query = "",
  selectedApp = "",
  limit = 200,
  offset = 0,
  loading = 0,
  player = null,
  zoom = 1,
  initial = true,
  lastSignature = "",
  toastTimer,
  debounce;
const colors = [
  "#8ac6b2",
  "#74aeca",
  "#b5abd3",
  "#c4b883",
  "#9bba9e",
  "#c291ab",
];
const dateKey = (t) => {
  const d = new Date(t * 1000);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};
const clock = (t) =>
  new Date(t * 1000).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
const shortClock = (t) =>
  new Date(t * 1000).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
const bytes = (n) =>
  n > 1e9
    ? (n / 1e9).toFixed(2) + " GB"
    : n > 1e6
      ? (n / 1e6).toFixed(1) + " MB"
      : Math.round(n / 1000) + " KB";
function color(bundle) {
  let h = 0;
  for (const c of bundle) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return colors[h % colors.length];
}
function node(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}
function toast(message) {
  $("toast").textContent = message;
  $("toast").classList.remove("hidden");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => $("toast").classList.add("hidden"), 4000);
}
function fail(error) {
  toast(error.message || String(error));
}
function bounds() {
  if (!$("date").value) return { from: 0, to: 1e15 };
  const d = new Date($("date").value + "T00:00:00"),
    next = new Date(d);
  next.setDate(next.getDate() + 1);
  return { from: d.getTime() / 1000, to: next.getTime() / 1000 };
}
function updateState(s) {
  state = s;
  $("recordState").classList.toggle("active", s.recording);
  $("recordState").replaceChildren(
    node("i"),
    document.createTextNode(s.captureState),
  );
  $("record").classList.toggle("recording", s.recording);
  $("recordLabel").textContent = s.recording
    ? "Pause recording"
    : "Start recording";
  $("notice").textContent = s.error || "";
  $("notice").classList.toggle("hidden", !s.error);
  $("recordState").title = s.captureState;
  $("emptyRecord").textContent = s.recording
    ? "Pause recording"
    : "Start recording";
  if (!current)
    $("frameTitle").textContent = s.recording
      ? s.captureState + " · switch to another app to capture"
      : "Recording is off until you start it.";
  const existing = $("appFilter").value;
  const select = $("appFilter");
  select.replaceChildren(new Option("All applications", ""));
  for (const a of s.apps)
    select.add(new Option(`${a.name} (${a.count})`, a.bundle));
  select.value = existing;
  if (initial) {
    $("date").value = dateKey(s.last || Date.now() / 1000);
    initial = false;
  }
}
async function refresh(force = false) {
  try {
    const s = await call("state");
    updateState(s);
    const signature = `${s.count}:${s.last}`;
    if (force || signature !== lastSignature) {
      lastSignature = signature;
      await load();
    }
  } catch (e) {
    if (!state) fail(e);
  }
}
async function load() {
  const seq = ++loading;
  const result = await call("frames", {
    query,
    app: selectedApp,
    ...bounds(),
    limit,
    offset,
  });
  if (seq !== loading) return;
  frames = result.slice().reverse();
  const keep = current && frames.find((f) => f.id === current.id);
  renderList();
  renderTimeline();
  if (keep) select(keep.id, false);
  else if (frames.length) select(frames[frames.length - 1].id, false);
  else showEmpty();
  $("loadMore").classList.toggle("hidden", result.length < limit);
  $("newer").classList.toggle("hidden", offset === 0);
  const d = new Date($("date").value + "T12:00:00");
  $("dayTitle").textContent =
    $("date").value === dateKey(Date.now() / 1000)
      ? "Today"
      : d.toLocaleDateString([], { month: "short", day: "numeric" });
  $("listLabel").textContent = query
    ? "Matching moments"
    : offset
      ? "Earlier moments"
      : "Captured moments";
  $("resultCount").textContent =
    result.length === limit ? `${result.length}+` : String(result.length);
}
function renderList() {
  const list = $("results");
  list.replaceChildren();
  if (!frames.length) {
    list.append(
      node(
        "div",
        "list-empty",
        query
          ? "No matches in this date and application. Try another phrase or date."
          : "No moments on this date. Start recording or import a screenshot.",
      ),
    );
    return;
  }
  for (const f of frames.slice().reverse()) {
    const b = node("button", "moment");
    b.dataset.id = f.id;
    b.setAttribute("aria-label", `${f.app}, ${clock(f.time)}, ${f.title}`);
    const img = node("img");
    img.src = `litt://frame/${f.id}`;
    img.alt = "";
    img.loading = "lazy";
    const content = node("div", "moment-main"),
      top = node("div", "moment-top"),
      dot = node("i");
    dot.style.background = color(f.bundle);
    top.append(
      dot,
      node("span", "", f.app),
      node("time", "", shortClock(f.time)),
    );
    const title = node(
      "div",
      "moment-title",
      query ? excerpt(f.text, query) : f.title || "Untitled window",
    );
    content.append(top, title);
    b.append(img, content);
    b.onclick = () => select(f.id);
    list.append(b);
  }
}
function excerpt(text, q) {
  const first = q.trim().split(/\s+/)[0]?.toLowerCase();
  const i = text.toLowerCase().indexOf(first);
  return i < 0
    ? text.slice(0, 100)
    : (i > 25 ? "…" : "") + text.slice(Math.max(0, i - 25), i + 90);
}
function select(id, scroll = true) {
  current = frames.find((f) => f.id === id);
  if (!current) return;
  $("empty").classList.add("hidden");
  for (const id of ["imageArea", "frameBadge", "prev", "next", "zoomControls"])
    $(id).classList.remove("hidden");
  $("screenshot").src = `litt://frame/${current.id}`;
  $("screenshot").alt =
    `${current.app} screenshot from ${new Date(current.time * 1000).toLocaleString()}`;
  $("currentApp").textContent = current.app;
  $("badgeApp").textContent = current.app;
  $("badgeDot").style.background = color(current.bundle);
  $("badgeTime").textContent = clock(current.time);
  $("frameTitle").textContent = current.title || "Untitled window";
  $("frameInfo").textContent =
    `${current.width} × ${current.height} · ${current.source === "import" ? "Imported screenshot" : "Screen capture"}`;
  $("playTime").textContent = clock(current.time);
  $("playDate").textContent = new Date(current.time * 1000).toLocaleDateString(
    [],
    { month: "short", day: "numeric" },
  );
  for (const id of ["textButton", "exportButton", "play", "back", "forward"])
    $(id).disabled = false;
  const index = frames.indexOf(current);
  $("prev").disabled = $("back").disabled = index === 0;
  $("next").disabled = $("forward").disabled = index === frames.length - 1;
  for (const b of $("results").children)
    b.classList.toggle("selected", Number(b.dataset.id) === id);
  if (scroll)
    $("results")
      .querySelector(".selected")
      ?.scrollIntoView({ block: "nearest", inline: "nearest" });
  fit();
  highlight();
  renderEvidence();
  positionPlayhead();
}
function showEmpty() {
  current = null;
  stopPlay();
  $("empty").classList.remove("hidden");
  for (const id of [
    "imageArea",
    "frameBadge",
    "prev",
    "next",
    "zoomControls",
    "playhead",
  ])
    $(id).classList.add("hidden");
  for (const id of ["textButton", "exportButton", "play", "back", "forward"])
    $(id).disabled = true;
  $("currentApp").textContent = query
    ? "No matching moments"
    : "Your screen, remembered";
  $("frameTitle").textContent = state?.recording
    ? state.captureState
    : "Recording is off until you start it.";
  $("frameInfo").textContent = "";
  $("playTime").textContent = "—";
  $("playDate").textContent = "";
  $("evidence").classList.add("hidden");
  $("screenshot").removeAttribute("src");
  const title = $("empty").querySelector("h2"),
    p = $("empty").querySelector("p");
  title.textContent = query
    ? "Nothing matches just yet."
    : "Your day has a rewind button.";
  p.textContent = query
    ? "Try fewer words, another date, or a different application."
    : "Keep the moments you might need again. Find a phrase, revisit a page, pick up a thought.";
}
function fit() {
  if (!current) return;
  const stage = $("stage");
  const ratio =
    Math.min(
      stage.clientWidth / current.width,
      stage.clientHeight / current.height,
    ) * zoom;
  $("imageCanvas").style.width = `${current.width * ratio}px`;
  $("imageCanvas").style.height = `${current.height * ratio}px`;
  $("zoomLabel").textContent =
    zoom === 1 ? "Fit" : `${Math.round(zoom * 100)}%`;
}
function highlight() {
  const boxes = $("boxes");
  boxes.replaceChildren();
  if (!current || !query.trim()) return;
  const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
  for (const b of current.boxes) {
    if (terms.some((t) => b.text.toLowerCase().includes(t))) {
      const box = node("div", "ocr-box");
      Object.assign(box.style, {
        left: b.x * 100 + "%",
        top: b.y * 100 + "%",
        width: b.w * 100 + "%",
        height: b.h * 100 + "%",
      });
      boxes.append(box);
    }
  }
}
function renderEvidence() {
  if (!current) return;
  const m = $("metadata");
  m.replaceChildren();
  for (const [key, val] of [
    ["Application", current.app],
    ["Bundle ID", current.bundle],
    ["Captured", new Date(current.time * 1000).toLocaleString()],
    [
      "Source",
      current.source === "import" ? "Imported image" : "ScreenCaptureKit",
    ],
    ["Resolution", `${current.width} × ${current.height}`],
    ["Frame ID", String(current.id)],
  ])
    m.append(node("dt", "", key), node("dd", "", val));
  $("ocrText").textContent = current.text || "No readable text was detected.";
}
function renderTimeline() {
  const ticks = $("ticks"),
    bands = $("bands"),
    legend = $("legend");
  ticks.replaceChildren();
  bands.replaceChildren();
  legend.replaceChildren();
  $("rangeLabel").textContent = frames.length
    ? `${frames.length} saved moment${frames.length === 1 ? "" : "s"}`
    : "No moments yet";
  $("timeline").setAttribute(
    "aria-valuemax",
    String(Math.max(0, frames.length - 1)),
  );
  if (!frames.length) return;
  const from = frames[0].time,
    to = frames[frames.length - 1].time;
  for (let i = 0; i < 5; i++)
    ticks.append(node("span", "", shortClock(from + ((to - from) * i) / 4)));
  const duration = Math.max(1, to - from);
  let group = null;
  const groups = [];
  for (let i = 0; i < frames.length; i++) {
    const f = frames[i];
    if (group && group.bundle === f.bundle && f.time - group.end < 60) {
      group.end = f.time;
      group.last = i;
    } else {
      group = {
        bundle: f.bundle,
        name: f.app,
        start: f.time,
        end: f.time,
        first: i,
        last: i,
      };
      groups.push(group);
    }
  }
  for (const g of groups) {
    const b = node("button", "band");
    b.style.background = color(g.bundle);
    const start = Math.min(99, ((g.start - from) / duration) * 100);
    const end = ((g.end - from) / duration) * 100;
    const width = frames.length === 1 ? 100 : Math.max(1, end - start);
    b.style.left = `${Math.min(99.5, start)}%`;
    b.style.width = `${Math.min(100 - start, width)}%`;
    b.title = `${g.name} · ${clock(g.start)} – ${clock(g.end)}`;
    if (width > 9) b.textContent = g.name;
    b.onclick = (e) => {
      e.stopPropagation();
      select(frames[g.first].id);
    };
    bands.append(b);
  }
  for (const [bundle, f] of new Map(frames.map((f) => [f.bundle, f]))) {
    const item = node("span", "legend-item"),
      dot = node("i");
    dot.style.background = color(bundle);
    item.append(dot, document.createTextNode(f.app));
    legend.append(item);
  }
}
function positionPlayhead() {
  if (!current || !frames.length) return;
  const pct =
    ((current.time - frames[0].time) /
      Math.max(1, frames[frames.length - 1].time - frames[0].time)) *
    100;
  $("playhead").classList.remove("hidden");
  $("playhead").style.left = `${Math.min(99.8, pct)}%`;
  $("timeline").setAttribute("aria-valuenow", String(frames.indexOf(current)));
  $("timeline").setAttribute(
    "aria-valuetext",
    `${current.app} at ${clock(current.time)}`,
  );
}
function move(delta) {
  if (!current) return;
  const i = frames.indexOf(current) + delta;
  if (i >= 0 && i < frames.length) select(frames[i].id);
  else if (delta > 0) stopPlay();
}
function stopPlay() {
  clearInterval(player);
  player = null;
  $("play").textContent = "▶";
  $("play").setAttribute("aria-label", "Play captured moments");
}
function play() {
  if (player) {
    stopPlay();
    return;
  }
  if (!frames.length) return;
  if (current?.id === frames[frames.length - 1].id) select(frames[0].id);
  $("play").textContent = "Ⅱ";
  $("play").setAttribute("aria-label", "Pause playback");
  player = setInterval(() => move(1), Number($("speed").value));
}
async function toggle() {
  try {
    $("record").disabled = true;
    updateState(await call("toggle"));
    if (state.error)
      toast("Screen Recording permission is needed. See the message above.");
  } catch (e) {
    fail(e);
  } finally {
    $("record").disabled = false;
  }
}
async function importScreens() {
  try {
    $("import").disabled = true;
    toast("Choose screenshots to import and index locally.");
    const result = await call("import");
    if (!result.cancelled) {
      $("date").value = dateKey(Date.now() / 1000);
      query = "";
      $("search").value = "";
      selectedApp = "";
      offset = 0;
      await refresh(true);
      toast(
        `${result.ids.length} screenshot${result.ids.length === 1 ? "" : "s"} indexed`,
      );
    }
  } catch (e) {
    fail(e);
  } finally {
    $("import").disabled = false;
  }
}
async function settings() {
  try {
    updateState(await call("state"));
    $("interval").value = state.settings.interval;
    $("retention").value = state.settings.retentionDays;
    const available = new Set(state.runningApps.map((a) => a.bundle));
    const list = $("excludedApps");
    list.replaceChildren();
    for (const a of state.runningApps) {
      const label = node("label"),
        input = node("input");
      input.type = "checkbox";
      input.value = a.bundle;
      input.checked = state.settings.excluded.includes(a.bundle);
      label.append(input, document.createTextNode(a.name));
      list.append(label);
    }
    $("customExcluded").value = state.settings.excluded
      .filter((b) => !available.has(b))
      .join(", ");
    $("permissionTitle").textContent = state.permission
      ? "Screen Recording permission granted"
      : "Screen Recording permission needed";
    $("permissionDescription").textContent = state.permission
      ? "Recording starts only when you enable it."
      : "Grant access in macOS, then restart Litt.";
    $("storageInfo").textContent =
      `${state.count} moments · ${bytes(state.diskBytes)} on disk`;
    $("performanceInfo").textContent = state.lastProcessingMs
      ? `Last saved capture: ${Math.round(state.lastProcessingMs)} ms processing · ${state.skippedThisSession} samples skipped this session`
      : "Capture performance appears after your first recording.";
    $("settingsDialog").showModal();
  } catch (e) {
    fail(e);
  }
}
function confirmAction(title, description, action) {
  $("confirmTitle").textContent = title;
  $("confirmDescription").textContent = description;
  $("confirmDialog").showModal();
  $("acceptConfirm").onclick = async () => {
    $("acceptConfirm").disabled = true;
    try {
      await action();
      $("confirmDialog").close();
      await refresh(true);
      toast("Deleted from your local archive.");
    } catch (e) {
      fail(e);
    } finally {
      $("acceptConfirm").disabled = false;
    }
  };
}
$("search").addEventListener("input", () => {
  clearTimeout(debounce);
  debounce = setTimeout(() => {
    query = $("search").value;
    limit = 200;
    offset = 0;
    stopPlay();
    $("clearSearch").classList.toggle("hidden", !query);
    load().catch(fail);
  }, 220);
});
$("clearSearch").onclick = () => {
  $("search").value = "";
  $("search").dispatchEvent(new Event("input"));
};
$("date").onchange = () => {
  limit = 200;
  offset = 0;
  stopPlay();
  load().catch(fail);
};
$("today").onclick = () => {
  $("date").value = dateKey(Date.now() / 1000);
  $("date").dispatchEvent(new Event("change"));
};
$("appFilter").onchange = () => {
  selectedApp = $("appFilter").value;
  limit = 200;
  offset = 0;
  load().catch(fail);
};
$("loadMore").onclick = () => {
  offset += limit;
  stopPlay();
  load().catch(fail);
};
$("newer").onclick = () => {
  offset = Math.max(0, offset - limit);
  stopPlay();
  load().catch(fail);
};
$("record").onclick = $("emptyRecord").onclick = toggle;
$("import").onclick = $("emptyImport").onclick = importScreens;
$("settingsButton").onclick = settings;
$("closeSettings").onclick = () => $("settingsDialog").close();
$("cancelConfirm").onclick = () => $("confirmDialog").close();
$("settingsForm").onsubmit = async (e) => {
  e.preventDefault();
  $("saveSettings").disabled = true;
  try {
    const excluded = [...$("excludedApps").querySelectorAll("input:checked")]
      .map((i) => i.value)
      .concat(
        $("customExcluded")
          .value.split(",")
          .map((s) => s.trim())
          .filter(Boolean),
      );
    updateState(
      await call("settings", {
        interval: Number($("interval").value),
        retentionDays: Number($("retention").value),
        excluded: [...new Set(excluded)],
      }),
    );
    $("settingsDialog").close();
    await refresh(true);
    toast("Settings saved.");
  } catch (error) {
    fail(error);
  } finally {
    $("saveSettings").disabled = false;
  }
};
$("permissionButton").onclick = () => call("permission").catch(fail);
$("reveal").onclick = () => call("reveal").catch(fail);
$("clearArchive").onclick = () =>
  confirmAction(
    "Delete all history?",
    "Recording will stop. All archived screenshots and their searchable text will be permanently deleted.",
    () => call("clear"),
  );
$("deleteFrame").onclick = () => {
  if (current) {
    const id = current.id;
    confirmAction(
      "Delete this moment?",
      "This removes the screenshot and its text from your local archive.",
      () => call("delete", { id }),
    );
  }
};
$("exportButton").onclick = () =>
  current &&
  call("export", { id: current.id })
    .then((r) => {
      if (!r.cancelled) toast("Screenshot exported.");
    })
    .catch(fail);
$("textButton").onclick = () => {
  $("evidence").classList.toggle("hidden");
  requestAnimationFrame(fit);
};
$("closeEvidence").onclick = () => {
  $("evidence").classList.add("hidden");
  requestAnimationFrame(fit);
};
$("copyText").onclick = () => {
  if (!current) return;
  (navigator.clipboard
    ? navigator.clipboard.writeText(current.text)
    : Promise.reject()
  )
    .then(() => toast("Recognized text copied."))
    .catch(() => {
      const range = document.createRange();
      range.selectNodeContents($("ocrText"));
      getSelection().removeAllRanges();
      getSelection().addRange(range);
      toast("Text selected. Press ⌘C to copy.");
    });
};
$("prev").onclick = $("back").onclick = () => move(-1);
$("next").onclick = $("forward").onclick = () => move(1);
$("play").onclick = play;
$("speed").onchange = () => {
  if (player) {
    stopPlay();
    play();
  }
};
$("zoomIn").onclick = () => {
  zoom = Math.min(3, zoom + 0.5);
  fit();
};
$("zoomOut").onclick = () => {
  zoom = Math.max(1, zoom - 0.5);
  fit();
};
let scrubbing = false;
function seek(e) {
  if (!frames.length) return;
  const r = $("timeline").getBoundingClientRect(),
    ratio = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
  const t =
    frames[0].time + ratio * (frames[frames.length - 1].time - frames[0].time);
  let closest = frames[0];
  for (const f of frames)
    if (Math.abs(f.time - t) < Math.abs(closest.time - t)) closest = f;
  select(closest.id);
}
$("timeline").onpointerdown = (e) => {
  if (e.target.closest(".band")) return;
  scrubbing = true;
  $("timeline").setPointerCapture(e.pointerId);
  seek(e);
};
$("timeline").onpointermove = (e) => {
  if (scrubbing) seek(e);
};
$("timeline").onpointerup = () => (scrubbing = false);
$("timeline").onpointercancel = () => (scrubbing = false);
document.addEventListener("keydown", (e) => {
  if (
    document.querySelector("dialog[open]") ||
    ["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName)
  )
    return;
  if (e.key === "Escape") {
    $("evidence").classList.add("hidden");
    $("textButton").focus();
  } else if (e.key === "/") {
    e.preventDefault();
    $("search").focus();
  } else if (e.key === "ArrowLeft") {
    e.preventDefault();
    move(-1);
  } else if (e.key === "ArrowRight") {
    e.preventDefault();
    move(1);
  } else if (e.code === "Space") {
    e.preventDefault();
    play();
  }
});
new ResizeObserver(fit).observe($("stage"));
window.runSmokeTest = async () => {
  try {
    const s = await call("state");
    updateState(s);
    await load();
    const checks = {
      nativeBridge: typeof s.count === "number",
      layout: document.documentElement.scrollWidth <= innerWidth,
      fullWidthViewer:
        $("stage").getBoundingClientRect().width > innerWidth * 0.9,
      noSidebar: !document.querySelector(".sidebar"),
      horizontalMoments: getComputedStyle($("results")).display === "flex",
      controlsVisible:
        document.querySelector(".timeline-panel").getBoundingClientRect()
          .bottom <= innerHeight,
      toolbarFits:
        document.querySelector(".archive-toolbar").scrollWidth <=
        document.querySelector(".archive-toolbar").clientWidth,
    };
    if (frames.length) {
      select(frames[0].id);
      await new Promise((r) => setTimeout(r, 400));
      checks.actualImage =
        $("screenshot").complete && $("screenshot").naturalWidth > 0;
      const first = current.id,
        word = current.text.match(/[A-Za-z]{5,}/)?.[0];
      if (word) {
        query = word;
        $("search").value = word;
        await load();
        checks.search = frames.some((f) => f.id === first);
        checks.highlights = $("boxes").children.length > 0;
      }
      if (frames.length > 1) {
        select(frames[0].id);
        move(1);
        checks.navigation = current.id === frames[1].id;
      }
      await settings();
      checks.settings = $("settingsDialog").open;
      $("settingsDialog").close();
      $("evidence").classList.remove("hidden");
      fit();
      checks.evidence = $("ocrText").textContent === current.text;
    } else {
      checks.empty = !$("empty").classList.contains("hidden");
      checks.captureOff = !s.recording;
    }
    window.smokeResult = {
      passed: Object.values(checks).every(Boolean),
      checks,
      count: s.count,
    };
  } catch (e) {
    window.smokeResult = { passed: false, error: e.message };
  }
};
refresh(true);
setInterval(() => refresh(), 2500);
