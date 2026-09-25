import datetime, json, os, subprocess, sys, time, urllib.error, urllib.request

def version_key(v):
    return [int(p) if p.isdigit() else 0 for p in str(v).split(".")]

def notes_for(version, script="FISCHXR.ahk"):
    try:
        lines = open(script, encoding="utf-8-sig").read().splitlines()
    except OSError:
        return []
    out, inside = [], False
    for ln in lines:
        s = ln.strip()
        if not inside:
            inside = s == version
            continue
        if s.startswith("- "):
            out.append(s)
        elif out or s:            
            break
    return out

def main():
    hook = os.environ.get("DISCORD_WEBHOOK", "").strip()
    if not hook:
        sys.exit("No DISCORD_WEBHOOK secret is set.")
    new = json.load(open("update.json", encoding="utf-8"))
    ver = new["version"]
    try:
        old = json.loads(subprocess.check_output(["git", "show", "HEAD~1:update.json"], stderr=subprocess.DEVNULL))
    except Exception:
        old = {}
    
    forced = os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
    if not forced and old.get("version") and version_key(ver) <= version_key(old["version"]):
        print(f"Version {ver} isn't newer than {old['version']}; nothing to announce.")
        return
    notes = notes_for(ver) or ([f"- {new['notes']}"] if new.get("notes") else [])
    bullets = "\n".join("• " + n[2:] for n in notes) or "• Fixes and improvements all round."
    repo = os.environ.get("GITHUB_REPOSITORY", "exoartar/FISCHXR")
    page = f"https://github.com/{repo}"
    text = (f"Here's what's new:\n\n{bullets}\n\n"
            f"New here? [Download the Macro from GitHub!]({page}).")
    if len(text) > 4000:
        text = text[:3990] + "…"
    embed = {
        "title": f"FISCHXR {ver} Has Released!",
        "url": page,
        "description": text,
        "color": 0x5865F2,
        "footer": {"text": "Update! · FISCHXR"},
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    payload = {"username": "FISCHXR", "embeds": [embed], "allowed_mentions": {"parse": []}}
    role = os.environ.get("DISCORD_ROLE", "").strip()
    if role:                        
        payload["content"] = f"<@&{role}>"
        payload["allowed_mentions"] = {"roles": [role]}
    body = json.dumps(payload).encode()
   
    for attempt in range(4):
        req = urllib.request.Request(hook, data=body, method="POST",
                                     headers={"Content-Type": "application/json", "User-Agent": "FISCHXR-announcer (github actions)"})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                print(f"Announced {ver} (HTTP {r.status}).")
                return
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == 3:
                raise
            wait = 2.0
            try:
                wait = float(json.loads(e.read() or b"{}").get("retry_after", wait))
            except Exception:
                wait = float(e.headers.get("Retry-After", wait) or wait)
            print(f"Discord asked to wait {wait:.1f} s; trying again.")
            time.sleep(min(max(wait, 0.5), 30))

if __name__ == "__main__":
    main()
