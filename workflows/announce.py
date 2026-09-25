import json, os, subprocess, sys, urllib.request

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
    if old.get("version") and version_key(ver) <= version_key(old["version"]):
        print(f"Version {ver} isn't newer than {old['version']}; nothing to announce.")
        return
    notes = notes_for(ver) or ([f"- {new['notes']}"] if new.get("notes") else [])
    text = "\n".join(notes) or "A new version is out."
    repo = os.environ.get("GITHUB_REPOSITORY", "exoartar/FISCHXR")
    embed = {
        "title": f"FISCHXR {ver} is out",
        "url": f"https://github.com/{repo}",
        "description": (text[:3900] + "\n...") if len(text) > 3900 else text,
        "color": 0x5865F2,
        "footer": {"text": "Running FISCHXR updates itself; or download it from GitHub."},
    }
    payload = {"username": "FISCHXR", "embeds": [embed], "allowed_mentions": {"parse": []}}
    role = os.environ.get("DISCORD_ROLE", "").strip()
    if role:                        # optional: ping an "updates" role
        payload["content"] = f"<@&{role}>"
        payload["allowed_mentions"] = {"roles": [role]}
    req = urllib.request.Request(hook, data=json.dumps(payload).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "User-Agent": "FISCHXR-announcer (github actions)"})
    with urllib.request.urlopen(req, timeout=20) as r:
        print(f"Announced {ver} (HTTP {r.status}).")

if __name__ == "__main__":
    main()
