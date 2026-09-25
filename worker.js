/**
 * The FISCHXR service: a small Cloudflare Worker between the FISCHXR bot and
 * every copy of the macro.
 *
 * It keeps, per Discord account (one KV record "u:<id>"):
 *   access       "grant" | "revoke" | ""   (Plus given or taken by the team; "" = Plus if boosting)
 *   blacklisted  true/false, reason        (not allowed to sign in to FISCHXR)
 *   seq, values  settings changed from Discord with /settings, each with its own number
 *   state        what the macro last reported (version, fishing, settings) for /status
 *
 * And for everyone (one record "cfg:locks"): versions of the macro locked to a
 * Discord role ({version: {role, roleName}}), read by every macro at /locks.
 *
 * The macro reads only its own record, proving who it is with the user's
 * Discord sign-in (checked with Discord on every call). The bot writes with
 * the admin key, which only the bot and this service know (the ADMIN_KEY secret).
 *
 * Bindings (Worker settings): KV namespace as DB, secret ADMIN_KEY.
 */
const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json" } });

const ID = /^\d{15,21}$/;
const MAX_VALUE = 120;

async function load(env, id) {
  const rec = await env.DB.get("u:" + id, "json");
  return rec || { access: "", blacklisted: false, reason: "", seq: 0, values: {}, state: null };
}
const save = (env, id, rec) => env.DB.put("u:" + id, JSON.stringify(rec));
const loadLocks = async (env) => (await env.DB.get("cfg:locks", "json")) || {};
// the locks, in a fixed shape (the macro reads it field by field)
const lockList = (locks) => Object.fromEntries(Object.entries(locks).map(([v, l]) => [v, { role: l.role, roleName: l.roleName || "" }]));

// Who a Discord sign-in belongs to (asked of Discord itself), or "".
async function whoIs(auth) {
  if (!/^Bearer [\w.\-]{10,}$/.test(auth || "")) return "";
  const r = await fetch("https://discord.com/api/v10/users/@me", {
    headers: { Authorization: auth, "User-Agent": "FISCHXR-service" },
  });
  if (r.status !== 200) return "";
  const u = await r.json();
  return ID.test(u.id || "") ? u.id : "";
}

// Constant-time comparison for the admin key.
function sameKey(a, b) {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    try {
      // ---------------------------------------------------------- the bot
      // ---------------------------------------------------------- everyone
      if (path === "/locks" && req.method === "GET") return json({ locks: lockList(await loadLocks(env)) });

      if (path.startsWith("/admin/")) {
        if (!sameKey(req.headers.get("x-admin-key") || "", env.ADMIN_KEY || "")) return json({ error: "forbidden" }, 403);
        const body = req.method === "POST" ? await req.json() : {};
        // version locks (not per user)
        if (path === "/admin/locks" && req.method === "GET") return json({ locks: lockList(await loadLocks(env)) });
        if (path === "/admin/lock" && req.method === "POST") {
          const version = String(body.version || "").trim();
          if (!/^\d+\.\d+\.\d+$/.test(version)) return json({ error: "bad version" }, 400);
          const locks = await loadLocks(env);
          if (body.on) {
            const role = String(body.role || "");
            if (!ID.test(role)) return json({ error: "bad role" }, 400);
            locks[version] = { role, roleName: String(body.roleName || "").slice(0, 100) };
          } else delete locks[version];
          await env.DB.put("cfg:locks", JSON.stringify(locks));
          return json({ ok: true, locks: lockList(locks) });
        }
        const id = String(body.id || url.searchParams.get("id") || "");
        if (!ID.test(id)) return json({ error: "bad id" }, 400);
        const rec = await load(env, id);
        if (path === "/admin/user" && req.method === "GET") return json({ id, ...rec });
        if (req.method !== "POST") return json({ error: "method" }, 405);
        if (path === "/admin/access") {
          const a = body.access === "grant" || body.access === "revoke" ? body.access : "";
          rec.access = a;
        } else if (path === "/admin/blacklist") {
          rec.blacklisted = !!body.on;
          rec.reason = rec.blacklisted ? String(body.reason || "").slice(0, 200) : "";
        } else if (path === "/admin/set") {
          const key = String(body.key || ""), value = String(body.value ?? "");
          if (!/^[a-z-]{2,30}$/.test(key) || value.length > MAX_VALUE) return json({ error: "bad setting" }, 400);
          rec.seq += 1;
          rec.values[key] = { v: value, seq: rec.seq };
        } else return json({ error: "not found" }, 404);
        await save(env, id, rec);
        return json({ ok: true, id, ...rec });
      }

      // ---------------------------------------------------------- a macro
      if (path === "/me" || path === "/me/state") {
        const id = await whoIs(req.headers.get("authorization"));
        if (!id) return json({ error: "sign in" }, 401);
        const rec = await load(env, id);
        if (path === "/me" && req.method === "GET") {
          const since = Number(url.searchParams.get("since") || 0) || 0;
          const changes = Object.entries(rec.values)
            .filter(([, c]) => c.seq > since)
            .sort((a, b) => a[1].seq - b[1].seq)
            .map(([key, c]) => ({ seq: c.seq, key, value: c.v }));
          return json({ id, access: rec.access, blacklisted: rec.blacklisted, reason: rec.reason, seq: rec.seq, changes, locks: lockList(await loadLocks(env)) });
        }
        if (path === "/me/state" && req.method === "PUT") {
          const s = await req.json();
          const state = {
            version: String(s.version || "").slice(0, 20),
            fishing: !!s.fishing,
            phase: String(s.phase || "").slice(0, 60),
            rod: String(s.rod || "").slice(0, 40),
            values: typeof s.values === "object" && s.values ? Object.fromEntries(
              Object.entries(s.values).slice(0, 40).map(([k, v]) => [String(k).slice(0, 30), String(v).slice(0, MAX_VALUE)])) : {},
          };
          // Stored only when it changed (KV writes are the scarce thing).
          const same = rec.state && JSON.stringify({ ...rec.state, at: 0 }) === JSON.stringify({ ...state, at: 0 });
          if (!same) {
            rec.state = { ...state, at: Date.now() };
            await save(env, id, rec);
          }
          return json({ ok: true, stored: !same });
        }
        return json({ error: "method" }, 405);
      }
      if (path === "/") return json({ service: "FISCHXR", ok: true });
      return json({ error: "not found" }, 404);
    } catch (e) {
      return json({ error: "server", detail: String(e).slice(0, 200) }, 500);
    }
  },
};
