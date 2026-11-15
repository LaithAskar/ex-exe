#!/usr/bin/env node
// Read-only X timeline + trends reader for Vex. Zero dependencies (Node 22+ built-in WebSocket/fetch).
//
// Uses a DEDICATED Chrome profile (~/.config/ex-exe/chrome-x), never your main Chrome profile.
// It never clicks, likes, posts, follows, or scrolls anything but the page itself.
//
//   node scripts/x_reader.mjs --login        one-time: opens a visible Chrome window; log into X yourself, then close it
//   node scripts/x_reader.mjs                headless read -> data/x_topics.json
//   node scripts/x_reader.mjs --fixture f.html   run the extractors against a local HTML file (tests)
//   node scripts/x_reader.mjs --status       print whether the profile looks logged in

import { spawn, execFileSync } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync, renameSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = process.env.EXE_X_OUT || join(ROOT, "data", "x_topics.json");
const PROFILE = process.env.EXE_X_PROFILE || join(homedir(), ".config", "ex-exe", "chrome-x");
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9333;
const args = process.argv.slice(2);
const flag = (f) => args.includes(f);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.error("[x_reader]", ...a);

function profileInUse() {
  try {
    execFileSync("pgrep", ["-f", `--user-data-dir=${PROFILE}`], { stdio: "ignore" });
    return true;
  } catch { return false; }
}

function launch({ headless, url, profile = PROFILE }) {
  mkdirSync(profile, { recursive: true });
  const a = [
    `--user-data-dir=${profile}`, "--no-first-run", "--no-default-browser-check",
    "--disable-extensions", "--disable-sync", "--mute-audio",
  ];
  if (headless) {
    a.push("--headless=new", `--remote-debugging-port=${PORT}`, "--remote-allow-origins=*", "--window-size=1200,2200");
  }
  a.push(url ?? "about:blank");
  return spawn(CHROME, a, { stdio: "ignore", detached: !headless });
}

async function cdpConnect() {
  for (let i = 0; i < 50; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${PORT}/json/version`);
      if (r.ok) break;
    } catch {}
    await sleep(200);
  }
  const t = await (await fetch(`http://127.0.0.1:${PORT}/json/new?about:blank`, { method: "PUT" })).json();
  const ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((ok, bad) => { ws.onopen = ok; ws.onerror = bad; });
  let id = 0;
  const pending = new Map();
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  };
  const send = (method, params = {}) => new Promise((ok, bad) => {
    const mid = ++id;
    pending.set(mid, (m) => (m.error ? bad(new Error(`${method}: ${m.error.message}`)) : ok(m.result)));
    ws.send(JSON.stringify({ id: mid, method, params }));
  });
  const evaluate = async (expr) => {
    const r = await send("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true });
    return r.result?.value;
  };
  return { ws, send, evaluate };
}

// --- extractors run INSIDE the page. Pure DOM reads. ---
const EXTRACT_TWEETS = `(() => {
  const out = [];
  for (const art of document.querySelectorAll('article[data-testid="tweet"]')) {
    if (/\\b(Promoted|Ad)\\b/.test(art.querySelector('[data-testid="placementTracking"]')?.innerText || "")) continue;
    if ([...art.querySelectorAll('span')].some(s => s.innerText === 'Ad' || s.innerText === 'Promoted')) continue;
    const text = art.querySelector('[data-testid="tweetText"]')?.innerText?.trim();
    if (!text) continue;
    const handle = [...art.querySelectorAll('[data-testid="User-Name"] span')].map(s => s.innerText).find(t => t.startsWith('@')) || null;
    const likeLabel = art.querySelector('[data-testid="like"], [data-testid="unlike"]')?.getAttribute('aria-label') || '';
    const m = likeLabel.replace(/,/g, '').match(/([\\d.]+)\\s*([KM]?)/i);
    const likes = m ? Math.round(parseFloat(m[1]) * ({ K: 1e3, M: 1e6 }[m[2].toUpperCase()] || 1)) : 0;
    const link = art.querySelector('a[href*="/status/"]')?.href || null;
    out.push({ text, handle, likes, url: link });
  }
  return out;
})()`;

const EXTRACT_TRENDS = `(() => {
  const out = [];
  for (const el of document.querySelectorAll('[data-testid="trend"]')) {
    const lines = el.innerText.split('\\n').map(s => s.trim()).filter(Boolean);
    const name = lines.find(l => !/^(\\d+\\s*·\\s*)?Trending|^·$|posts$|^\\d+$|^Only on X/i.test(l) && !/^[\\d.,]+[KM]?$/i.test(l));
    const context = lines.find(l => /Trending/i.test(l)) || null;
    if (name) out.push({ name, context });
  }
  return out;
})()`;

const LOGIN_WALL = `(() => {
  const u = location.href;
  if (/\\/login|\\/i\\/flow|\\/logout/.test(u) || u === 'https://x.com/' ) return true;
  return !!document.querySelector('[data-testid="loginButton"], a[href="/login"]') && !document.querySelector('[data-testid="SideNav_AccountSwitcher_Button"]');
})()`;

async function waitFor(evaluate, expr, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const v = await evaluate(expr).catch(() => null);
    if (v) return v;
    await sleep(500);
  }
  return null;
}

async function goto(send, url) {
  await send("Page.navigate", { url });
  await sleep(1500);
}

function shorten(s, n) {
  s = s.replace(/\s+/g, " ").replace(/https?:\/\/\S+/g, "").trim();
  return s.length > n ? s.slice(0, n - 1).trimEnd() + "…" : s;
}

export function toTopics(tweets, trends) {
  const seen = new Set();
  const topics = [];
  for (const t of trends.slice(0, 10)) {
    if (seen.has(t.name)) continue;
    seen.add(t.name);
    topics.push({ title: `${t.name} (trending on X)`, url: null, source: "x", kind: "trend" });
  }
  const ranked = [...tweets].filter((t) => t.text.length >= 25).sort((a, b) => b.likes - a.likes).slice(0, 12);
  for (const t of ranked) {
    const key = t.text.slice(0, 40);
    if (seen.has(key)) continue;
    seen.add(key);
    topics.push({ title: `${t.handle ?? "someone"} on X: ${shorten(t.text, 90)}`, url: t.url, source: "x", kind: "tweet" });
  }
  return topics;
}

function writeOut(payload) {
  mkdirSync(dirname(OUT), { recursive: true });
  const tmp = OUT + ".tmp";
  writeFileSync(tmp, JSON.stringify(payload, null, 2));
  renameSync(tmp, OUT);
}

async function read({ fixture }) {
  if (!fixture && !existsSync(PROFILE)) {
    log("no X profile yet. Run: node scripts/x_reader.mjs --login");
    return 3;
  }
  if (profileInUse()) { log("X profile is open (login window?). Skipping this run."); return 4; }

  // Fixtures use a throwaway profile so tests never create/touch the real X profile.
  const profile = fixture ? join(process.env.TMPDIR || "/tmp", `ex-exe-fixture-${process.pid}`) : PROFILE;
  const chrome = launch({ headless: true, profile });
  const killer = setTimeout(() => { log("timeout"); chrome.kill("SIGKILL"); process.exit(5); }, 75_000);
  try {
    const { send, evaluate, ws } = await cdpConnect();
    await send("Page.enable");
    // Headless Chrome advertises itself; present as normal desktop Chrome.
    const { userAgent } = await send("Browser.getVersion");
    await send("Network.setUserAgentOverride", { userAgent: userAgent.replace("HeadlessChrome", "Chrome") });

    let tweets = [], trends = [];
    if (fixture) {
      await goto(send, pathToFileURL(resolve(fixture)).href);
      tweets = await evaluate(EXTRACT_TWEETS);
      trends = await evaluate(EXTRACT_TRENDS);
    } else {
      await goto(send, "https://x.com/home");
      const ready = await waitFor(evaluate, `document.querySelector('article[data-testid="tweet"]') ? 'feed' : (${LOGIN_WALL} ? 'wall' : null)`, 25_000);
      if (ready !== "feed") {
        log(ready === "wall" ? "not logged in (login wall). Run: node scripts/x_reader.mjs --login" : "timeline never loaded");
        writeOut({ updated: new Date().toISOString(), loggedIn: ready !== "wall" ? null : false, topics: [] });
        return 3;
      }
      for (let i = 0; i < 3; i++) {
        tweets.push(...(await evaluate(EXTRACT_TWEETS)));
        await evaluate("window.scrollBy(0, 1800)");
        await sleep(1800);
      }
      await goto(send, "https://x.com/explore/tabs/trending");
      await waitFor(evaluate, `document.querySelector('[data-testid="trend"]')`, 12_000);
      trends = (await evaluate(EXTRACT_TRENDS)) ?? [];
    }
    ws.close();
    const uniq = [...new Map(tweets.map((t) => [t.text, t])).values()];
    const topics = toTopics(uniq, trends);
    if (fixture) {
      console.log(JSON.stringify({ tweets: uniq, trends, topics }, null, 2));
    } else {
      writeOut({ updated: new Date().toISOString(), loggedIn: true, topics });
      log(`wrote ${topics.length} topics (${trends.length} trends, ${uniq.length} tweets) -> ${OUT}`);
    }
    return 0;
  } finally {
    clearTimeout(killer);
    chrome.kill("SIGTERM");
  }
}

async function main() {
  if (flag("--login")) {
    if (profileInUse()) { log("login window already open"); return 0; }
    launch({ headless: false, url: "https://x.com/login" }).unref();
    console.log("A separate Chrome window opened with Vex's X profile.\nLog into X there yourself, then just close that window. Your main Chrome is untouched.");
    return 0;
  }
  if (flag("--status")) {
    console.log(existsSync(join(PROFILE, "Default", "Cookies")) ? "profile exists (run a read to confirm login)" : "no profile; run --login");
    return 0;
  }
  const fi = args.indexOf("--fixture");
  return read({ fixture: fi >= 0 ? args[fi + 1] : null });
}

const isMain = (() => { try { return realpathSync(fileURLToPath(import.meta.url)) === realpathSync(process.argv[1]); } catch { return false; } })();
if (isMain) {
  main().then((c) => process.exit(c ?? 0), (e) => { log(e.stack || e); process.exit(1); });
}
