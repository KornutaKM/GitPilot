/**
 * RC3 Cloudflare GitHub App OAuth token gateway.
 * The GitHub client secret is server-only; never reflect, log or cache tokens.
 * Public POST endpoints require a Cloudflare rate-limit binding.
 */
const headers = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store, max-age=0",
  "pragma": "no-cache",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer"
};
const response = (body, status = 200) => new Response(JSON.stringify(body), { status, headers });

const publicJSON = value => new Response(value, { status: 200, headers: {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "public, max-age=600",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer"
} });

function domainAssociation(request, env, path) {
  if (request.method !== "GET" || new URL(request.url).search)
    return response({ error: "not_found" }, 404);
  const raw = path.endsWith("apple-app-site-association")
    ? env.APPLE_APP_SITE_ASSOCIATION : env.ANDROID_ASSETLINKS;
  if (!raw || typeof raw !== "string" || raw.length > 16_384)
    return response({ error: "not_configured" }, 503);
  try {
    const value = JSON.parse(raw);
    if (path.endsWith("apple-app-site-association")) {
      if (!Array.isArray(value?.applinks?.details) || !value.applinks.details.length)
        throw new Error("invalid_association");
    } else if (!Array.isArray(value) || !value.length) {
      throw new Error("invalid_association");
    }
    return publicJSON(JSON.stringify(value));
  } catch {
    return response({ error: "not_configured" }, 503);
  }
}

const validToken = value => typeof value === "string" &&
  value.length >= 10 && value.length <= 2000 && /^[A-Za-z0-9._~-]+$/.test(value);
const validVerifier = value => typeof value === "string" &&
  /^[A-Za-z0-9._~-]{43,128}$/.test(value);
const validLifetime = value => Number.isSafeInteger(value) &&
  value > 0 && value <= 63_072_000;

async function readJSONLimited(request, maxBytes = 8192) {
  if (Number(request.headers.get("content-length") || 0) > maxBytes)
    throw new Error("too_large");
  if (!request.body) throw new Error("invalid_json");
  const reader = request.body.getReader();
  const buffers = [];
  let bytes = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maxBytes) {
        await reader.cancel();
        throw new Error("too_large");
      }
      buffers.push(value);
    }
  } finally { reader.releaseLock(); }
  const all = new Uint8Array(bytes);
  let at = 0;
  for (const part of buffers) { all.set(part, at); at += part.byteLength; }
  try { return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(all)); }
  catch { throw new Error("invalid_json"); }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/health" && request.method === "GET") return response({ ok: true });
    if (["/.well-known/apple-app-site-association", "/.well-known/assetlinks.json"].includes(url.pathname)) {
      return domainAssociation(request, env, url.pathname);
    }
    if (url.pathname === "/oauth/callback" && request.method === "GET") {
      // Never echo OAuth code or state if the associated-domain handoff fails.
      return new Response("Return to GitPilot and retry sign-in. This page does not authorize access.", {
        status: 200, headers: { "content-type": "text/plain; charset=utf-8",
          "cache-control": "no-store", "referrer-policy": "no-referrer",
          "x-content-type-options": "nosniff" }
      });
    }
    if (!["/oauth/exchange", "/oauth/refresh"].includes(url.pathname))
      return response({ error: "not_found" }, 404);
    if (request.method !== "POST") return response({ error: "method_not_allowed" }, 405);
    if (url.search || url.hash) return response({ error: "invalid_request" }, 400);
    if (!(request.headers.get("content-type") ?? "").startsWith("application/json"))
      return response({ error: "content_type" }, 415);
    if (!env.GITHUB_CLIENT_ID || !env.GITHUB_CLIENT_SECRET ||
        !env.GITHUB_CALLBACK_URI || !env.AUTH_RATE_LIMIT) {
      return response({ error: "not_configured" }, 503);
    }
    const ip = request.headers.get("cf-connecting-ip");
    if (!ip || ip.length > 64) return response({ error: "not_configured" }, 503);
    try {
      const { success } = await env.AUTH_RATE_LIMIT.limit({ key: `${url.pathname}:${ip}` });
      if (!success) return response({ error: "rate_limited" }, 429);
    } catch {
      return response({ error: "rate_limit_unavailable" }, 503);
    }
    let input;
    try { input = await readJSONLimited(request); }
    catch (error) {
      return response({ error: error.message === "too_large" ? "too_large" : "invalid_json" },
                      error.message === "too_large" ? 413 : 400);
    }
    if (!input || typeof input !== "object" || Array.isArray(input))
      return response({ error: "invalid_request" }, 400);
    const isRefresh = url.pathname === "/oauth/refresh";
    if (isRefresh
        ? !validToken(input.refresh_token)
        : !validToken(input.code) || !validVerifier(input.code_verifier)) {
      return response({ error: "invalid_request" }, 400);
    }
    const params = new URLSearchParams({
      client_id: env.GITHUB_CLIENT_ID, client_secret: env.GITHUB_CLIENT_SECRET
    });
    if (isRefresh) {
      params.set("grant_type", "refresh_token");
      params.set("refresh_token", input.refresh_token);
    } else {
      params.set("code", input.code);
      params.set("code_verifier", input.code_verifier);
      // Never accept redirect_uri or client_secret from untrusted native clients.
      params.set("redirect_uri", env.GITHUB_CALLBACK_URI);
    }
    try {
      const upstream = await fetch("https://github.com/login/oauth/access_token", {
        method: "POST", redirect: "manual", signal: AbortSignal.timeout(12_000),
        headers: {
          accept: "application/json", "content-type": "application/x-www-form-urlencoded",
          "cache-control": "no-store"
        },
        body: params.toString()
      });
      if (!upstream.ok) return response({ error: "upstream_unavailable" }, 502);
      const data = await readJSONLimited(upstream, 16_384);
      if (!data || typeof data !== "object" || Array.isArray(data) || data.error ||
          !validToken(data.access_token) || !validToken(data.refresh_token) ||
          !validLifetime(data.expires_in) || !validLifetime(data.refresh_token_expires_in)) {
        return response({ error: "github_denied" }, 401);
      }
      return response({
        access_token: data.access_token, expires_in: data.expires_in,
        refresh_token: data.refresh_token, refresh_token_expires_in: data.refresh_token_expires_in
      });
    } catch {
      return response({ error: "upstream_unavailable" }, 502);
    }
  }
};
