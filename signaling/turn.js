// TURN credential minting. Deliberately pure and dependency-free: it takes an
// explicit config rather than reading process.env, and requires nothing but
// node's own crypto.
//
// Split out of server.js for two reasons. The unit test can then run in CI with
// no `npm install` at all — server.js pulls in `ws`, node_modules is gitignored,
// and the first version of this test failed on exactly that. And taking config as
// an argument means the test states the config it is testing instead of
// relaunching node with a doctored environment.

const crypto = require("crypto");

// Short by design: a leaked credential is only useful until it expires, and a
// lobby only needs one long enough to finish the handshake.
const DEFAULT_TTL_SEC = 600;
const DEFAULT_STUN = ["stun:stun.l.google.com:19302"];

/**
 * TURN REST API credentials (draft-uberti-behave-turn-rest-00), the scheme coturn
 * implements via use-auth-secret / static-auth-secret. coturn recomputes this
 * HMAC to validate, so it needs no user database.
 *
 * The tag makes each peer's username distinct, so coturn's user-quota applies per
 * peer rather than to everyone who joined inside one TTL window. The HMAC covers
 * the whole username, tag included — hashing only the timestamp would give every
 * peer in a window the same valid password.
 */
function turnCredentials(secret, ttlSec, nowMs, tag) {
  const expiry = Math.floor(nowMs / 1000) + ttlSec;
  const username = `${expiry}:${tag}`;
  const credential = crypto.createHmac("sha1", secret).update(username).digest("base64");
  return { username, credential };
}

/**
 * The ICE server list to hand a joining client.
 *
 * A relay is only advertised when both a URL and a secret are configured: an
 * unauthenticated turn: URL would fail every allocation while still costing
 * gathering time, which looks like a broken relay rather than an absent one.
 */
function iceServers(config, nowMs = Date.now(), randomTag = null) {
  const stunUrls = config.stunUrls && config.stunUrls.length ? config.stunUrls : DEFAULT_STUN;
  const ttlSec = config.turnTtlSec || DEFAULT_TTL_SEC;
  const servers = [];
  if (stunUrls.length) servers.push({ urls: stunUrls });
  if (config.turnUrls && config.turnUrls.length && config.turnSecret) {
    const tag = randomTag || crypto.randomBytes(4).toString("hex");
    const { username, credential } = turnCredentials(config.turnSecret, ttlSec, nowMs, tag);
    servers.push({ urls: config.turnUrls, username, credential });
  }
  return servers;
}

/** One line for the startup log: a misconfigured relay should be obvious there. */
function relaySummary(config) {
  if (!config.turnUrls || !config.turnUrls.length) {
    return "none configured — set TURN_URLS and TURN_SECRET to hand out a relay";
  }
  if (!config.turnSecret) {
    return `${config.turnUrls.join(", ")} IGNORED — TURN_SECRET is not set`;
  }
  return `${config.turnUrls.join(", ")} (ephemeral creds, ${config.turnTtlSec || DEFAULT_TTL_SEC}s)`;
}

module.exports = { turnCredentials, iceServers, relaySummary, DEFAULT_TTL_SEC, DEFAULT_STUN };
