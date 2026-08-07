// Unit test for TURN credential minting. Prints ICE_TEST_OK / ICE_TEST_FAIL.
//
// Requires only ./turn.js, which depends on nothing but node's crypto — so this
// runs in CI with no `npm install`. The first version required server.js and died
// on `Cannot find module 'ws'`, since node_modules is gitignored; it passed
// locally only because mine were installed.
//
// Worth testing at all because the failure is invisible: a wrong HMAC makes coturn
// refuse every allocation, so the game looks exactly as it did with no relay. The
// vector below is fixed, so a change to the scheme fails here instead of in
// production.

const crypto = require("crypto");
const turn = require("./turn.js");

const failures = [];
function check(cond, label) {
  if (!cond) failures.push(label);
}

const SECRET = "test-secret";
const NOW_MS = 1_700_000_000_000; // fixed, so the vector is stable
const TTL = 600;

// --- Fixed vector -----------------------------------------------------------
//   username = <unix expiry>:<tag>
//   password = base64(HMAC-SHA1(secret, username))
const got = turn.turnCredentials(SECRET, TTL, NOW_MS, "abcd1234");
check(got.username === "1700000600:abcd1234", `username was ${got.username}`);
// Cross-checked against an independent Python HMAC before being pinned here.
check(got.credential === "edEGMecD0c/FN5WykkCnfRAEHXg=",
  `credential was ${got.credential}`);

// Recomputed independently of turn.js as well: a test that calls the same helper
// it is testing only proves self-consistency.
check(got.credential === crypto.createHmac("sha1", SECRET)
  .update("1700000600:abcd1234").digest("base64"),
  "credential is the HMAC of the whole username");

// The password must cover the tag, not just the timestamp — otherwise every peer
// inside one TTL window shares a valid password.
check(got.credential !== crypto.createHmac("sha1", SECRET)
  .update("1700000600").digest("base64"),
  "credential covers the tag, not just the expiry");

// --- Expiry -----------------------------------------------------------------
check(Number(turn.turnCredentials(SECRET, 60, NOW_MS, "x").username.split(":")[0])
  === 1_700_000_060, "ttl is added to the current time, in seconds");
check(Number(turn.turnCredentials(SECRET, 600, NOW_MS, "x").username.split(":")[0]) >
  Number(turn.turnCredentials(SECRET, 60, NOW_MS, "x").username.split(":")[0]),
  "a longer ttl expires later");

// --- Distinctness -----------------------------------------------------------
check(turn.turnCredentials(SECRET, TTL, NOW_MS, "aaaa").credential !==
  turn.turnCredentials(SECRET, TTL, NOW_MS, "bbbb").credential,
  "different peers get different credentials");
check(turn.turnCredentials("other-secret", TTL, NOW_MS, "abcd1234").credential !==
  got.credential, "a different secret yields a different credential");

// --- What a client actually receives ----------------------------------------
const noRelay = turn.iceServers({ turnUrls: [], turnSecret: "" }, NOW_MS, "tag");
check(noRelay.length === 1, "a STUN entry is always offered");
check(!JSON.stringify(noRelay).includes("turn:"),
  "no relay is advertised when none is configured");
check(!noRelay.some((s) => "credential" in s),
  "no credentials are sent when there is no relay");

// URLs but no secret must NOT advertise a relay: an unauthenticated turn: URL
// fails every allocation while still costing gathering time, which looks like a
// broken relay rather than an absent one.
const urlsOnly = turn.iceServers(
  { turnUrls: ["turn:relay.example:3478"], turnSecret: "" }, NOW_MS, "tag");
check(!JSON.stringify(urlsOnly).includes("turn:"),
  "a relay without a secret is not advertised");
check(turn.relaySummary({ turnUrls: ["turn:relay.example:3478"], turnSecret: "" })
  .includes("IGNORED"), "the startup log calls out urls with no secret");

const withRelay = turn.iceServers({
  turnUrls: ["turn:relay.example:3478", "turns:relay.example:5349"],
  turnSecret: "s3cret",
  turnTtlSec: 300,
}, NOW_MS, "beef");
const relay = withRelay.find((s) => JSON.stringify(s.urls).includes("turn:"));
check(relay !== undefined, "a configured relay is advertised");
check(relay && relay.urls.length === 2, "every configured relay url is passed through");
check(relay && relay.username === "1700000300:beef",
  `the relay username honours the configured ttl (was ${relay && relay.username})`);
check(relay && typeof relay.credential === "string" && relay.credential.length > 0,
  "the relay entry carries a credential");
// The secret itself must never reach a client.
check(!JSON.stringify(withRelay).includes("s3cret"),
  "the shared secret is absent from what clients receive");
// STUN is still offered alongside, so a direct path is still attempted first.
check(withRelay.some((s) => JSON.stringify(s.urls).includes("stun:")),
  "stun is still offered alongside the relay");

if (failures.length) {
  console.log(`ICE_TEST_FAIL: ${failures.join(", ")}`);
  process.exit(1);
}
console.log(`ICE_TEST_OK (18 checks)`);
