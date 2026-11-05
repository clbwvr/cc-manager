#!/usr/bin/env python3
"""
cc-web: a tiny, dependency-free web UI for browsing/searching/resuming Claude Code
conversations from a phone on the home LAN. Reuses the same data cc-manager reads:
  ~/.claude/projects/*/*.jsonl        (conversation transcripts)
  ~/.claude/cc-manager.json           (custom titles, bases, projects, assignments)
  ~/.claude/cc-manager-cache.json     (parsed-session cache written by the Swift app)

"Resume" starts `claude --resume <id>` in a tmux session named "cc"; you then attach
from Termius (~/bin/cc-attach.sh) to interact. LAN-only, no auth (see README note).
"""
import json, os, re, html, shlex, subprocess, threading, time
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs


def watch_parent():
    """Exit when the launching process (cc-manager.app) goes away, so the phone UI
    is tied to the desktop app being open — even if the app crashes."""
    ppid = os.environ.get("CC_WEB_PARENT_PID")
    if not ppid:
        return
    ppid = int(ppid)
    while True:
        time.sleep(2)
        try:
            os.kill(ppid, 0)          # probe; raises if gone
            if os.getppid() == 1:     # reparented to launchd => parent died
                os._exit(0)
        except OSError:
            os._exit(0)

HOME = Path.home()
PROJECTS = HOME / ".claude" / "projects"
META = HOME / ".claude" / "cc-manager.json"
CACHE = HOME / ".claude" / "cc-manager-cache.json"
RESUME_SH = str(HOME / "bin" / "cc-resume.sh")
PORT = 8787
SEARCH_CAP = 200_000
PREVIEW_LIMIT = 12


def load_json(p):
    try:
        with open(p, "r", errors="ignore") as f:
            return json.load(f)
    except Exception:
        return None


def extract_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = [b.get("text", "") for b in content
                 if isinstance(b, dict) and isinstance(b.get("text"), str)]
        return "\n".join(p for p in parts if p)
    return ""


def looks_like_tool_result(content):
    return isinstance(content, list) and any(
        isinstance(b, dict) and b.get("type") == "tool_result" for b in content)


def quick_parse(path):
    """Mirror of the Swift JSONLParser for files not covered by the cache."""
    try:
        with open(path, "r", errors="ignore") as f:
            content = f.read()
    except Exception:
        return None
    cwd = first_user = ""
    count = 0
    previews, searchable, slen = [], [], 0
    ai_title = ""
    last_prompts = []
    for line in content.split("\n"):
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if not isinstance(obj, dict):
            continue
        t = obj.get("type")
        if t == "ai-title":
            if obj.get("aiTitle"):
                ai_title = obj["aiTitle"]
            continue
        if t == "last-prompt":
            if obj.get("lastPrompt"):
                last_prompts.append(obj["lastPrompt"])
            continue
        if t not in ("user", "assistant"):
            continue
        side = bool(obj.get("isSidechain", False))
        if not cwd and isinstance(obj.get("cwd"), str):
            cwd = obj["cwd"]
        msg = obj.get("message") or {}
        text = extract_text(msg.get("content"))
        if not side and text:
            count += 1
            if t == "user" and not first_user and not looks_like_tool_result(msg.get("content")):
                first_user = text
            if len(previews) < PREVIEW_LIMIT:
                previews.append({"role": t, "text": text[:4000]})
            if slen < SEARCH_CAP:
                s = text.lower()
                searchable.append(s)
                slen += len(s)
    if count == 0:
        if not ai_title and not last_prompts:
            return None
        title = ai_title or (last_prompts[-1] if last_prompts else "")
        return {"cwd": cwd, "firstUserMessage": title,
                "messageCount": max(1, len(last_prompts)),
                "previews": [{"role": "user", "text": p} for p in last_prompts[-PREVIEW_LIMIT:]],
                "searchableText": "\n".join(last_prompts + [ai_title]).lower()}
    return {"cwd": cwd, "firstUserMessage": first_user, "messageCount": count,
            "previews": previews, "searchableText": "\n".join(searchable)}


_aititle_cache = {}


def ai_title_for(path, mtime):
    """Claude Code's AI-summarized title (`ai-title` line). Read lazily and memoized
    per (path, mtime); only JSON-parse lines that mention ai-title."""
    hit = _aititle_cache.get(path)
    if hit and hit[0] == mtime:
        return hit[1]
    title = ""
    try:
        with open(path, "r", errors="ignore") as f:
            for line in f:
                if "ai-title" not in line:
                    continue
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if o.get("type") == "ai-title" and o.get("aiTitle"):
                    title = o["aiTitle"]
    except OSError:
        pass
    _aititle_cache[path] = (mtime, title)
    return title


def load_conversations():
    meta = load_json(META) or {}
    custom = meta.get("customTitles", {})
    bases = set(meta.get("bases", []))
    conv_proj = meta.get("conversationProjects", {})
    projects = {p["id"]: p for p in meta.get("projects", [])}
    cache = load_json(CACHE) or {}

    convs = []
    if PROJECTS.is_dir():
        for d in PROJECTS.iterdir():
            if not d.is_dir():
                continue
            for f in d.glob("*.jsonl"):
                try:
                    st = f.stat()
                except OSError:
                    continue
                key = str(f)
                c = cache.get(key)
                if not (c and abs(c.get("modified", -1) - st.st_mtime) < 1
                        and c.get("size") == st.st_size):
                    c = quick_parse(key)
                    if c is None:
                        continue
                sid = f.stem
                title = (custom.get(sid) or ai_title_for(key, st.st_mtime)
                         or c.get("firstUserMessage") or "(untitled)")
                pid = conv_proj.get(sid)
                convs.append({
                    "id": sid,
                    "title": title,
                    "cwd": c.get("cwd", ""),
                    "projectName": os.path.basename(c.get("cwd", "")) or "—",
                    "project": projects.get(pid, {}).get("name") if pid else None,
                    "messageCount": c.get("messageCount", 0),
                    "isBase": sid in bases,
                    "mtime": st.st_mtime,
                    "previews": c.get("previews", []),
                    "_search": (c.get("searchableText", "") + " " + title + " " + c.get("cwd", "")).lower(),
                })
    convs.sort(key=lambda x: x["mtime"], reverse=True)
    return convs


def rel_age(mtime):
    import time
    d = max(0, time.time() - mtime)
    for unit, s in (("y", 31536000), ("mo", 2592000), ("d", 86400), ("h", 3600), ("m", 60)):
        if d >= s:
            return f"{int(d // s)}{unit} ago"
    return "just now"


def list_payload(q=""):
    q = q.strip().lower()
    out = []
    for c in load_conversations():
        if q and q not in c["_search"]:
            continue
        out.append({k: c[k] for k in ("id", "title", "projectName", "project",
                                      "messageCount", "isBase")} | {"age": rel_age(c["mtime"])})
    return out


def detail_payload(sid):
    for c in load_conversations():
        if c["id"] == sid:
            return {"id": sid, "title": c["title"], "project": c["project"],
                    "projectName": c["projectName"], "messageCount": c["messageCount"],
                    "cwd": c["cwd"], "previews": c["previews"]}
    return None


def do_resume(sid):
    cwd = ""
    for c in load_conversations():
        if c["id"] == sid:
            cwd = c["cwd"]
            break
    cmd = f"{shlex.quote(RESUME_SH)} {shlex.quote(sid)} {shlex.quote(cwd)}"
    subprocess.run(["tmux", "kill-session", "-t", "cc"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    r = subprocess.run(["tmux", "new-session", "-d", "-s", "cc", cmd],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        return False, r.stderr.decode("utf-8", "ignore") or "tmux failed"
    return True, "Resumed ✓ Now tap 'Open in Termius' below."


PAGE = """<!doctype html><html lang=en><head>
<meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>cc-manager</title>
<meta name=apple-mobile-web-app-capable content=yes>
<meta name=apple-mobile-web-app-status-bar-style content=black-translucent>
<meta name=apple-mobile-web-app-title content=cc-manager>
<link rel=apple-touch-icon href=/icon.png>
<style>
:root{--bg:#000;--card:#1c1c1e;--card2:#2c2c2e;--txt:#fff;--sub:#8e8e93;--acc:#0a84ff;--yel:#ffd60a}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{margin:0;background:var(--bg);color:var(--txt);font:16px/1.4 -apple-system,system-ui,sans-serif;
padding-bottom:env(safe-area-inset-bottom)}
header{position:sticky;top:0;background:rgba(0,0,0,.8);backdrop-filter:blur(20px);
padding:12px 16px calc(10px);border-bottom:.5px solid #333;z-index:5}
h1{margin:0 0 10px;font-size:22px;font-weight:700}
#q{width:100%;padding:11px 14px;border:none;border-radius:11px;background:var(--card2);
color:var(--txt);font-size:17px}
#q::placeholder{color:var(--sub)}
.list{padding:8px 12px 40px}
.row{display:block;background:var(--card);border-radius:14px;padding:13px 15px;margin:9px 0;
text-decoration:none;color:inherit;border:none;width:100%;text-align:left;font:inherit}
.row:active{background:var(--card2)}
.t{font-size:16px;font-weight:600;display:flex;gap:7px;align-items:baseline}
.t .star{color:var(--yel);flex:none}
.title-txt{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.meta{color:var(--sub);font-size:13px;margin-top:4px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.pill{display:inline-block;background:var(--card2);color:var(--sub);border-radius:6px;
padding:1px 7px;font-size:12px;margin-right:6px}
.count{color:var(--sub);text-align:center;padding:10px;font-size:13px}
/* detail */
#detail{position:fixed;inset:0;background:var(--bg);transform:translateX(100%);
transition:transform .22s ease;overflow-y:auto;z-index:10;display:flex;flex-direction:column}
#detail.open{transform:none}
.dhead{position:sticky;top:0;background:rgba(0,0,0,.85);backdrop-filter:blur(20px);
padding:12px 16px;border-bottom:.5px solid #333;display:flex;gap:12px;align-items:center}
.back{color:var(--acc);font-size:17px;background:none;border:none;padding:0;font-weight:500}
.dbody{padding:14px 16px 30px}
.dtitle{font-size:21px;font-weight:700;margin:4px 0 10px}
.msg{background:var(--card);border-radius:12px;padding:11px 13px;margin:9px 0;white-space:pre-wrap;
word-break:break-word;font-size:14px}
.msg .role{font-size:11px;text-transform:uppercase;letter-spacing:.5px;color:var(--sub);margin-bottom:5px}
.msg.user{background:#0a2a4a}
.idbox{background:var(--card);border-radius:12px;padding:12px 14px;margin:4px 0 14px}
.lbl{color:var(--sub);font-size:12px;margin-bottom:5px}
code.sel{display:block;background:#000;border-radius:8px;padding:9px 11px;font:13px/1.35 ui-monospace,Menlo,monospace;
color:var(--acc);word-break:break-all;user-select:all;-webkit-user-select:all}
.resume{position:sticky;bottom:0;margin:0;padding:14px 16px calc(14px + env(safe-area-inset-bottom));
background:rgba(0,0,0,.85);backdrop-filter:blur(20px);border-top:.5px solid #333}
.resume button,.resume a{display:block;width:100%;box-sizing:border-box;padding:15px;border:none;
border-radius:13px;font-size:17px;font-weight:600;text-align:center;text-decoration:none}
.resume button{background:var(--acc);color:#fff}
.resume a.open{background:var(--card2);color:var(--acc);margin-top:9px}
.resume button:active,.resume a:active{opacity:.7}
.toast{position:fixed;left:50%;bottom:90px;transform:translateX(-50%);background:var(--card2);
color:#fff;padding:12px 18px;border-radius:12px;font-size:14px;max-width:88%;text-align:center;
opacity:0;transition:opacity .2s;z-index:20;pointer-events:none}
.toast.show{opacity:1}
</style></head><body>
<header><h1>Conversations</h1><input id=q placeholder="Search" autocomplete=off autocapitalize=off></header>
<div class=count id=count></div>
<div class=list id=list></div>
<div id=detail><div class=dhead><button class=back onclick="history.back()">‹ Back</button></div>
<div class=dbody id=dbody></div>
<div class=resume><button onclick="resume()">▶ Resume this conversation</button>
<a class=open href="ssh://calebweaver@calebs-macbook-pro-3.tail33f43d.ts.net">Open in Termius ↗</a></div></div>
<div class=toast id=toast></div>
<script>
let cur=null, timer=null;
const esc=s=>(s||'').replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
async function load(q){
  const r=await fetch('/api/list?q='+encodeURIComponent(q||''));
  const d=await r.json();
  document.getElementById('count').textContent=d.length+' conversation'+(d.length==1?'':'s');
  document.getElementById('list').innerHTML=d.map(c=>`
   <button class=row onclick="openDetail('${c.id}')">
    <div class=t>${c.isBase?'<span class=star>★</span>':''}<span class=title-txt>${esc(c.title)}</span></div>
    <div class=meta>${c.project?'<span class=pill>'+esc(c.project)+'</span>':''}${esc(c.projectName)} · ${c.messageCount} msgs · ${c.age}</div>
   </button>`).join('');
}
document.getElementById('q').addEventListener('input',e=>{
  clearTimeout(timer);timer=setTimeout(()=>load(e.target.value),180);
});
async function openDetail(id){
  const r=await fetch('/api/detail?id='+id);const c=await r.json();cur=id;
  document.getElementById('dbody').innerHTML=
   `<div class=dtitle>${esc(c.title)}</div>
    <div class=meta style="margin-bottom:14px">${esc(c.projectName)} · ${c.messageCount} msgs</div>
    <div class=idbox>
      <div class=lbl>Conversation ID · long-press to copy</div>
      <code class=sel>${c.id}</code>
      <div class=lbl style="margin-top:11px">Or paste into Termius (inside cc-attach):</div>
      <code class=sel>cd ${esc(c.cwd||'~')} && claude --resume ${c.id}</code>
    </div>`+
   (c.previews||[]).map(m=>`<div class="msg ${m.role}"><div class=role>${m.role}</div>${esc(m.text)}</div>`).join('')
   +`<div class=meta style="margin-top:14px">${esc(c.cwd)}</div>`;
  document.getElementById('detail').classList.add('open');
  history.pushState({detail:1},'');
}
function closeDetail(){document.getElementById('detail').classList.remove('open');cur=null;}
window.addEventListener('popstate',()=>{
  if(document.getElementById('detail').classList.contains('open')) closeDetail();
});
function toast(t){const e=document.getElementById('toast');e.textContent=t;e.classList.add('show');
  setTimeout(()=>e.classList.remove('show'),3400);}
async function resume(){
  if(!cur)return;
  const r=await fetch('/api/resume',{method:'POST',headers:{'content-type':'application/json'},
    body:JSON.stringify({id:cur})});
  const d=await r.json();toast(d.ok?('✓ '+d.message):('✕ '+d.message));
}
load('');
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        b = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):
        pass

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/":
            return self._send(200, PAGE, "text/html; charset=utf-8")
        if u.path == "/icon.png":
            try:
                with open(Path(__file__).parent / "icon.png", "rb") as f:
                    return self._send(200, f.read(), "image/png")
            except OSError:
                return self._send(404, b"", "image/png")
        if u.path == "/api/list":
            q = parse_qs(u.query).get("q", [""])[0]
            return self._send(200, json.dumps(list_payload(q)))
        if u.path == "/api/detail":
            sid = parse_qs(u.query).get("id", [""])[0]
            d = detail_payload(sid)
            return self._send(200 if d else 404, json.dumps(d or {"error": "not found"}))
        self._send(404, json.dumps({"error": "not found"}))

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/api/resume":
            n = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(n) or b"{}")
            sid = data.get("id", "")
            if not sid:
                return self._send(400, json.dumps({"ok": False, "message": "no id"}))
            ok, msg = do_resume(sid)
            return self._send(200, json.dumps({"ok": ok, "message": msg}))
        self._send(404, json.dumps({"error": "not found"}))


if __name__ == "__main__":
    threading.Thread(target=watch_parent, daemon=True).start()
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), H)
    print(f"cc-web on http://0.0.0.0:{PORT}  (phone: http://Calebs-MacBook-Pro.local:{PORT})")
    srv.serve_forever()
