import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/worker.mjs";

const limiter = { limit: async () => ({ success: true }) };
const env = {
  GITHUB_CLIENT_ID: "Iv1_public_client_id",
  GITHUB_CLIENT_SECRET: "test-server-secret",
  GITHUB_CALLBACK_URI: "https://login.gitpilot.test/oauth/callback",
  AUTH_RATE_LIMIT: limiter
};
const verifier = "X".repeat(43);
const valid = {
  access_token: "ghu_test_access_token", expires_in: 28800,
  refresh_token: "ghr_test_refresh_token", refresh_token_expires_in: 15897600
};
function request(path, value, overrides = {}) {
  return new Request("https://login.gitpilot.test" + path, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": "198.51.100.1",
      ...overrides.headers
    },
    body: typeof value === "string" ? value : JSON.stringify(value)
  });
}
const post = (path, value, options = {}) =>
  worker.fetch(request(path, value, options), options.env ?? env);

test("rejects missing configuration and all unknown or unsafe routes", async () => {
  assert.equal((await post("/oauth/exchange", { code: "authorizationcode123", code_verifier: verifier },
                           { env: {} })).status, 503);
  assert.equal((await post("/oauth/exchange?leak=true", {
    code: "authorizationcode123", code_verifier: verifier
  })).status, 400);
  assert.equal((await worker.fetch(new Request("https://login.gitpilot.test/unknown"), env)).status, 404);
  assert.equal((await worker.fetch(new Request("https://login.gitpilot.test/health"), env)).status, 200);
  assert.equal((await worker.fetch(new Request("https://login.gitpilot.test/oauth/refresh"), env)).status, 405);
});

test("code exchange keeps GitHub App secret on server and fixes redirect_uri", async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async (url, options) => {
      assert.equal(url, "https://github.com/login/oauth/access_token");
      assert.equal(options.method, "POST");
      assert.equal(options.redirect, "manual");
      const params = new URLSearchParams(options.body);
      assert.equal(params.get("client_secret"), env.GITHUB_CLIENT_SECRET);
      assert.equal(params.get("client_id"), env.GITHUB_CLIENT_ID);
      assert.equal(params.get("code_verifier"), verifier);
      assert.equal(params.get("code"), "authorizationcode123");
      assert.equal(params.get("redirect_uri"), env.GITHUB_CALLBACK_URI);
      assert.equal(params.get("grant_type"), null);
      return new Response(JSON.stringify(valid), { status: 200 });
    };
    const output = await post("/oauth/exchange", {
      code: "authorizationcode123", code_verifier: verifier,
      redirect_uri: "https://evil.test/steal", client_secret: "forged"
    });
    assert.equal(output.status, 200);
    assert.equal((await output.json()).refresh_token, valid.refresh_token);
    assert.match(output.headers.get("cache-control"), /no-store/);
    assert.equal(output.headers.get("referrer-policy"), "no-referrer");
    assert.equal(output.headers.get("x-content-type-options"), "nosniff");
  } finally { globalThis.fetch = original; }
});

test("refresh rotates complete credentials without reflecting server secret", async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async (url, options) => {
      assert.equal(url, "https://github.com/login/oauth/access_token");
      const params = new URLSearchParams(options.body);
      assert.equal(params.get("grant_type"), "refresh_token");
      assert.equal(params.get("refresh_token"), "ghr_previous_refresh");
      assert.equal(params.get("client_secret"), env.GITHUB_CLIENT_SECRET);
      return new Response(JSON.stringify(valid), { status: 200 });
    };
    const answer = await post("/oauth/refresh", { refresh_token: "ghr_previous_refresh" });
    assert.equal(answer.status, 200);
    const text = await answer.text();
    assert.ok(!text.includes(env.GITHUB_CLIENT_SECRET));
    assert.deepEqual(JSON.parse(text), valid);
  } finally { globalThis.fetch = original; }
});

test("provider rejection never reflects error_description, tokens, or provider internals", async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async () => new Response(JSON.stringify({
      error: "invalid_grant", error_description: "PRIVATE-CODE-SHOULD-NOT-LEAK"
    }), { status: 200 });
    const rejected = await post("/oauth/refresh", { refresh_token: "ghr_previous_refresh" });
    assert.equal(rejected.status, 401);
    assert.deepEqual(await rejected.json(), { error: "github_denied" });
  } finally { globalThis.fetch = original; }
});

test("incomplete, malformed and header-injecting token pairs fail closed", async () => {
  const original = globalThis.fetch;
  const payload = { code: "authorizationcode123", code_verifier: verifier };
  try {
    const candidates = [
      { access_token: valid.access_token },
      { ...valid, refresh_token: undefined },
      { ...valid, expires_in: -1 },
      { ...valid, refresh_token_expires_in: "tomorrow" },
      { ...valid, refresh_token: "secret\r\nHeader: stolen" },
      { ...valid, access_token: "bad space token" },
      { ...valid, expires_in: 63_072_001 },
      { ...valid, refresh_token_expires_in: 0 },
      [valid]
    ];
    for (const data of candidates) {
      globalThis.fetch = async () => new Response(JSON.stringify(data), { status: 200 });
      const answer = await post("/oauth/exchange", payload);
      assert.equal(answer.status, 401);
      assert.deepEqual(await answer.json(), { error: "github_denied" });
    }
  } finally { globalThis.fetch = original; }
});

test("blocked caller and missing trusted Cloudflare IP fail before upstream", async () => {
  const seen = [];
  const rateEnv = { ...env, AUTH_RATE_LIMIT: { limit: async ({ key }) => {
    seen.push(key); return { success: false };
  } } };
  const answer = await post("/oauth/refresh", { refresh_token: "ghr_previous_refresh" },
                            { env: rateEnv });
  assert.equal(answer.status, 429);
  assert.deepEqual(seen, ["/oauth/refresh:198.51.100.1"]);
  const unavailable = { ...env, AUTH_RATE_LIMIT: { limit: async () => {
    throw new Error("rate limiter outage");
  } } };
  assert.equal((await post("/oauth/refresh", { refresh_token: "ghr_previous_refresh" },
                           { env: unavailable })).status, 503);
  assert.equal((await post("/oauth/refresh", { refresh_token: "ghr_previous_refresh" },
                           { headers: { "cf-connecting-ip": "" } })).status, 503);
});

test("oversized JSON is refused with and without Content-Length", async () => {
  const payload = JSON.stringify({ code: "X".repeat(12_000), code_verifier: verifier });
  const answer = await post("/oauth/exchange", payload);
  assert.equal(answer.status, 413);
  assert.deepEqual(await answer.json(), { error: "too_large" });
  assert.equal((await post("/oauth/exchange", "{not-json")).status, 400);
});

test("malformed OAuth code and PKCE verifier never reach GitHub", async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async () => { throw new Error("must not reach upstream"); };
    assert.equal((await post("/oauth/refresh", {
      refresh_token: "ghr_attack\nAuthorization"
    })).status, 400);
    assert.equal((await post("/oauth/exchange", {
      code: "bad code with spaces", code_verifier: verifier
    })).status, 400);
    assert.equal((await post("/oauth/exchange", {
      code: "authorizationcode123", code_verifier: "too-short"
    })).status, 400);
  } finally { globalThis.fetch = original; }
});

test("upstream timeouts, abnormal status and response bombs are sanitized", async () => {
  const original = globalThis.fetch;
  const input = { code: "authorizationcode123", code_verifier: verifier };
  try {
    globalThis.fetch = async () => { throw new Error("sensitive-upstream-body"); };
    const outage = await post("/oauth/exchange", input);
    assert.equal(outage.status, 502);
    assert.ok(!(await outage.text()).includes("sensitive"));
    globalThis.fetch = async () => new Response(JSON.stringify(valid), { status: 503 });
    assert.equal((await post("/oauth/exchange", input)).status, 502);
    globalThis.fetch = async () => new Response(JSON.stringify({
      ...valid, arbitrary: "x".repeat(60_000)
    }), { status: 200 });
    assert.equal((await post("/oauth/exchange", input)).status, 502);
  } finally { globalThis.fetch = original; }
});

test("domain-association endpoints return only valid public documents", async () => {
  const assocEnv = {
    ...env,
    APPLE_APP_SITE_ASSOCIATION: JSON.stringify({
      applinks: { details: [{ appIDs: ["ABCDEFGHIJ.dev.gitpilot.ios"],
        components: [{ "/": "/oauth/callback" }] }] }
    }),
    ANDROID_ASSETLINKS: JSON.stringify([{
      relation: ["delegate_permission/common.handle_all_urls"],
      target: { namespace: "android_app", package_name: "dev.gitpilot.android" }
    }])
  };
  for (const path of ["/.well-known/apple-app-site-association",
                      "/.well-known/assetlinks.json"]) {
    const ok = await worker.fetch(new Request("https://login.gitpilot.test" + path), assocEnv);
    assert.equal(ok.status, 200);
    assert.match(ok.headers.get("cache-control"), /max-age=600/);
    assert.ok(!(await ok.text()).includes(env.GITHUB_CLIENT_SECRET));
    assert.equal((await worker.fetch(new Request("https://login.gitpilot.test" + path),
                                     env)).status, 503);
    assert.equal((await worker.fetch(new Request("https://login.gitpilot.test" +
                  path + "?code=secret"), assocEnv)).status, 404);
  }
});

test("browser callback fallback does not echo code, state, token or query", async () => {
  const response = await worker.fetch(new Request(
    "https://login.gitpilot.test/oauth/callback?code=SUPER_PRIVATE_CODE&state=SECRET_STATE"), env);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const body = await response.text();
  assert.ok(!body.includes("SUPER_PRIVATE_CODE"));
  assert.ok(!body.includes("SECRET_STATE"));
});

test("public endpoints are never allowed to return unverified association files", async () => {
  const assocEnv = {
    ...env, APPLE_APP_SITE_ASSOCIATION: "{ malformed",
    ANDROID_ASSETLINKS: "[]"
  };
  for (const path of ["/.well-known/apple-app-site-association",
                      "/.well-known/assetlinks.json"]) {
    assert.equal((await worker.fetch(new Request("https://login.gitpilot.test" +
                  path), assocEnv)).status, 503);
  }
});
