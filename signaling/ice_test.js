// Unit test for the TURN credential minting. Prints ICE_TEST_OK / ICE_TEST_FAIL.
//
// Worth testing rather than eyeballing: the HMAC has to match byte for byte what
// coturn computes, and a wrong one fails in the least helpful way possible — the
// relay silently refuses every allocation, so the game looks exactly like it did
// with no relay at all. The expected value below is a fixed vector, so if the
// scheme ever changes it fails here instead of in production.

const assert = require("assert");
const crypto = require("crypto");
const { turnCredentials } = require("./server.js");

const failures = [];
function check(cond, label) {
  if (!cond) failures.push(label);
}

// --- Fixed vector -----------------------------------------------------------
// TURN REST API (draft-uberti-behave-turn-rest-00), which coturn implements:
//   username = <unix expiry>:<tag>
//   password = base64(HMAC-SHA1(secret, username))
const SECRET = "test-secret";
const NOW_MS = 1_700_000_000_000; // fixed, so the vector is stable
const TTL = 600;
const got = turnCredentials(SECRET, TTL, NOW_MS, "abcd1234");

check(got.username === "1700000600:abcd1234", `username was ${got.username}`);

// Recomputed here independently of server.js rather than reusing its own helper:
// a test that calls the same function it is testing only proves consistency.
const expected = crypto
  .createHmac("sha1", SECRET)
  .update("1700000600:abcd1234")
  .digest("base64");
check(got.credential === expected, "credential is the HMAC of the whole username");

// The password must cover the tag too, not just the timestamp — otherwise every
// peer in a TTL window shares one valid password.
const timestampOnly = crypto
  .createHmac("sha1", SECRET)
  .update("1700000600")
  .digest("base64");
check(got.credential !== timestampOnly, "credential covers the tag, not just the expiry");

// --- Expiry -----------------------------------------------------------------
check(
  Number(turnCredentials(SECRET, 60, NOW_MS, "x").username.split(":")[0]) === 1_700_000_060,
  "ttl is added to the current time, in seconds"
);
check(
  Number(turnCredentials(SECRET, 600, NOW_MS, "x").username.split(":")[0]) >
    Number(turnCredentials(SECRET, 60, NOW_MS, "x").username.split(":")[0]),
  "a longer ttl expires later"
);

// --- Distinctness -----------------------------------------------------------
// Different tags must give different credentials, so coturn's per-user quotas
// apply per peer instead of to everyone who joined in the same TTL window.
check(
  turnCredentials(SECRET, TTL, NOW_MS, "aaaa").credential !==
    turnCredentials(SECRET, TTL, NOW_MS, "bbbb").credential,
  "different peers get different credentials"
);
// And the secret must actually matter.
check(
  turnCredentials("other-secret", TTL, NOW_MS, "abcd1234").credential !== got.credential,
  "a different secret yields a different credential"
);

// --- No secret, no relay ----------------------------------------------------
// iceServers() is read from a fresh process below, because the module reads its
// env at load time.
const { execFileSync } = require("child_process");
function iceWithEnv(env) {
  const out = execFileSync(
    process.execPath,
    ["-e", "process.stdout.write(JSON.stringify(require('./server.js').iceServers()))"],
    { cwd: __dirname, env: { ...process.env, ...env } }
  );
  return JSON.parse(out.toString());
}

const noRelay = iceWithEnv({ TURN_URLS: "", TURN_SECRET: "" });
check(noRelay.length >= 1, "a STUN entry is always offered");
check(
  !noRelay.some((s) => JSON.stringify(s.urls).includes("turn:")),
  "no relay is advertised when none is configured"
);
check(
  !noRelay.some((s) => "credential" in s),
  "no credentials are sent when there is no relay"
);

// Configured but with no secret must NOT advertise a relay: an unauthenticated
// turn: URL would just fail every allocation and waste gathering time.
const urlsOnly = iceWithEnv({ TURN_URLS: "turn:relay.example:3478", TURN_SECRET: "" });
check(
  !urlsOnly.some((s) => JSON.stringify(s.urls).includes("turn:")),
  "a relay without a secret is not advertised"
);

const withRelay = iceWithEnv({
  TURN_URLS: "turn:relay.example:3478,turns:relay.example:5349",
  TURN_SECRET: "s3cret",
});
const relay = withRelay.find((s) => JSON.stringify(s.urls).includes("turn:"));
check(relay !== undefined, "a configured relay is advertised");
check(relay && relay.urls.length === 2, "every configured relay url is passed through");
check(relay && typeof relay.username === "string" && relay.username.includes(":"),
  "the relay entry carries an ephemeral username");
check(relay && typeof relay.credential === "string" && relay.credential.length > 0,
  "the relay entry carries a credential");
// The secret itself must never leave the hub.
check(JSON.stringify(withRelay).indexOf("s3cret") === -1,
  "the shared secret is not present in what clients receive");

if (failures.length) {
  console.log(`ICE_TEST_FAIL: ${failures.join(", ")}`);
  process.exit(1);
}
console.log(`ICE_TEST_OK (${13} checks)`);
