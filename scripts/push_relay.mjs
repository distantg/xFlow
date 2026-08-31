#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import http2 from "node:http2";
import path from "node:path";

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || "127.0.0.1";
const MAP_PATH = process.env.XFLOW_DEVICE_MAP_PATH || path.resolve("dist/push-device-map.json");
const RELAY_TOKEN = String(process.env.XFLOW_PUSH_RELAY_TOKEN || "").trim();
const ADMIN_TOKEN = String(process.env.XFLOW_PUSH_ADMIN_TOKEN || "").trim();
const MAX_JSON_BYTES = 64 * 1024;
const MAX_ACCOUNTS_PER_DEVICE = 20;
const MAX_STORED_DEVICES = 10_000;
const MAX_STORE_BYTES = 10 * 1024 * 1024;
const MAX_PUSH_RECIPIENTS = 250;
const DEVICE_MAPPING_MAX_AGE_MS = 90 * 24 * 60 * 60 * 1000;

const APNS_ENV = process.env.APNS_ENV || "development";
const APNS_HOST = APNS_ENV === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
const APNS_KEY_ID = process.env.APNS_KEY_ID || "";
const APNS_TEAM_ID = process.env.APNS_TEAM_ID || "";
const APNS_BUNDLE_ID = process.env.APNS_BUNDLE_ID || "";
const APNS_AUTH_KEY_PATH = process.env.APNS_AUTH_KEY_PATH || "";

if (RELAY_TOKEN.length < 32) {
  console.error("XFLOW_PUSH_RELAY_TOKEN must contain at least 32 characters.");
  process.exit(1);
}
if (ADMIN_TOKEN.length < 32) {
  console.error("XFLOW_PUSH_ADMIN_TOKEN must contain at least 32 characters.");
  process.exit(1);
}
if (ADMIN_TOKEN === RELAY_TOKEN) {
  console.error("The sync and admin relay tokens must be different.");
  process.exit(1);
}
if (!Number.isInteger(PORT) || PORT < 1 || PORT > 65535) {
  console.error("PORT must be an integer from 1 through 65535.");
  process.exit(1);
}
if (APNS_ENV !== "development" && APNS_ENV !== "production") {
  console.error("APNS_ENV must be development or production.");
  process.exit(1);
}

function ensureStoreFile() {
  fs.mkdirSync(path.dirname(MAP_PATH), { recursive: true });
  if (!fs.existsSync(MAP_PATH)) {
    fs.writeFileSync(MAP_PATH, JSON.stringify({ devices: {} }, null, 2), {
      mode: 0o600,
      flag: "wx"
    });
  } else {
    const metadata = fs.lstatSync(MAP_PATH);
    if (metadata.isSymbolicLink() || !metadata.isFile()) {
      throw new Error("Device map path must be a regular file, not a symbolic link.");
    }
    if (metadata.size > MAX_STORE_BYTES) {
      throw new Error("Device map is unexpectedly large.");
    }
  }
  fs.chmodSync(MAP_PATH, 0o600);
}

function readStore() {
  ensureStoreFile();
  try {
    const parsed = JSON.parse(fs.readFileSync(MAP_PATH, "utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { devices: {} };
    }
    if (!parsed.devices || typeof parsed.devices !== "object" || Array.isArray(parsed.devices)) {
      parsed.devices = {};
    }
    return parsed;
  } catch {
    return { devices: {} };
  }
}

function writeStore(data) {
  ensureStoreFile();
  const temporaryPath = `${MAP_PATH}.${process.pid}.${crypto.randomUUID()}.tmp`;
  fs.writeFileSync(temporaryPath, JSON.stringify(data, null, 2), {
    mode: 0o600,
    flag: "wx"
  });
  fs.renameSync(temporaryPath, MAP_PATH);
  fs.chmodSync(MAP_PATH, 0o600);
}

function json(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff"
  });
  res.end(JSON.stringify(body));
}

function readJSON(req) {
  return new Promise((resolve, reject) => {
    const contentType = String(req.headers["content-type"] || "")
      .split(";", 1)[0]
      .trim()
      .toLowerCase();
    if (contentType !== "application/json") {
      const error = new Error("unsupported_media_type");
      error.statusCode = 415;
      req.resume();
      reject(error);
      return;
    }

    const chunks = [];
    let byteCount = 0;
    let tooLarge = false;
    req.on("data", (chunk) => {
      byteCount += chunk.length;
      if (byteCount > MAX_JSON_BYTES) {
        tooLarge = true;
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      if (tooLarge) {
        const error = new Error("payload_too_large");
        error.statusCode = 413;
        reject(error);
        return;
      }
      try {
        const raw = Buffer.concat(chunks).toString("utf8");
        resolve(raw ? JSON.parse(raw) : {});
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

function isAuthorized(req, expectedToken) {
  const prefix = "Bearer ";
  const header = String(req.headers.authorization || "");
  if (!header.startsWith(prefix)) return false;

  const provided = Buffer.from(header.slice(prefix.length), "utf8");
  const expected = Buffer.from(expectedToken, "utf8");
  return provided.length === expected.length && crypto.timingSafeEqual(provided, expected);
}

function isUUID(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function isDeviceToken(value) {
  return /^[0-9a-f]{64,200}$/i.test(value) && value.length % 2 === 0;
}

function sanitizedText(value, fallback, maximumLength) {
  const text = String(value || fallback)
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .trim();
  return (text || fallback).slice(0, maximumLength);
}

function base64url(input) {
  const raw = typeof input === "string" ? Buffer.from(input) : input;
  return raw.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function createJwt() {
  if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_AUTH_KEY_PATH) {
    throw new Error("Missing APNS_KEY_ID, APNS_TEAM_ID, or APNS_AUTH_KEY_PATH");
  }

  const privateKey = fs.readFileSync(APNS_AUTH_KEY_PATH, "utf8");
  const header = base64url(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID }));
  const claims = base64url(JSON.stringify({ iss: APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) }));
  const message = `${header}.${claims}`;

  const signature = crypto
    .createSign("sha256")
    .update(message)
    .end()
    .sign({ key: privateKey, dsaEncoding: "ieee-p1363" });
  return `${message}.${base64url(signature)}`;
}

function sendApns(token, payload) {
  if (!APNS_BUNDLE_ID) {
    return Promise.resolve({ ok: false, status: 0, error: "Missing APNS_BUNDLE_ID" });
  }

  let jwt;
  try {
    jwt = createJwt();
  } catch (error) {
    return Promise.resolve({ ok: false, status: 0, error: String(error.message || error) });
  }

  return new Promise((resolve) => {
    const client = http2.connect(APNS_HOST);
    client.on("error", (error) => {
      resolve({ ok: false, status: 0, error: error.message });
    });

    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${token}`,
      authorization: `bearer ${jwt}`,
      "apns-topic": APNS_BUNDLE_ID,
      "apns-push-type": "alert",
      "content-type": "application/json"
    });

    let statusCode = 0;
    let body = "";
    request.on("response", (headers) => {
      statusCode = Number(headers[":status"] || 0);
    });
    request.on("data", (chunk) => {
      body += chunk;
    });
    request.on("end", () => {
      client.close();
      resolve({
        ok: statusCode >= 200 && statusCode < 300,
        status: statusCode,
        body: body || undefined
      });
    });
    request.on("error", (error) => {
      client.close();
      resolve({ ok: false, status: statusCode, error: error.message });
    });

    request.end(JSON.stringify(payload));
  });
}

function uniqueTokensForAccount(store, accountID) {
  const tokens = [];
  const oldestAllowed = Date.now() - DEVICE_MAPPING_MAX_AGE_MS;
  for (const [token, entry] of Object.entries(store.devices || {})) {
    const updatedAt = Date.parse(entry?.updatedAt || "");
    if (!Number.isFinite(updatedAt) || updatedAt < oldestAllowed || !isDeviceToken(token)) {
      continue;
    }
    const accounts = Array.isArray(entry.accounts) ? entry.accounts : [];
    if (accounts.some((account) => account?.id === accountID)) {
      tokens.push(token);
    }
  }
  return [...new Set(tokens)];
}

function pruneExpiredDevices(store) {
  const oldestAllowed = Date.now() - DEVICE_MAPPING_MAX_AGE_MS;
  let didChange = false;
  for (const [token, entry] of Object.entries(store.devices || {})) {
    const updatedAt = Date.parse(entry?.updatedAt || "");
    if (!isDeviceToken(token) || !Number.isFinite(updatedAt) || updatedAt < oldestAllowed) {
      delete store.devices[token];
      didChange = true;
    }
  }
  return didChange;
}

function purgeExpiredDeviceMappings() {
  const store = readStore();
  if (pruneExpiredDevices(store)) {
    writeStore(store);
  }
}

try {
  purgeExpiredDeviceMappings();
} catch (error) {
  console.error(`Could not initialize the device map: ${String(error.message || error)}`);
  process.exit(1);
}

const cleanupTimer = setInterval(purgeExpiredDeviceMappings, 24 * 60 * 60 * 1000);
cleanupTimer.unref();

const server = http.createServer(async (req, res) => {
  if (!req.url) {
    return json(res, 404, { error: "not_found" });
  }

  if (req.method === "GET" && req.url === "/health") {
    return json(res, 200, { ok: true, apnsEnv: APNS_ENV });
  }

  if (req.method === "POST" && req.url === "/v1/devices/sync") {
    if (!isAuthorized(req, RELAY_TOKEN)) {
      return json(res, 401, { error: "unauthorized" });
    }
    try {
      const payload = await readJSON(req);
      const deviceToken = String(payload.deviceToken || "").trim();
      const activeAccountID = String(payload.activeAccountID || "").trim();
      const rawAccounts = Array.isArray(payload.accounts) ? payload.accounts : [];
      const accounts = rawAccounts
        .slice(0, MAX_ACCOUNTS_PER_DEVICE)
        .map((account) => ({ id: String(account?.id || "").trim() }))
        .filter((account) => isUUID(account.id));
      const uniqueAccountIDs = new Set(accounts.map((account) => account.id));

      if (!isDeviceToken(deviceToken)) {
        return json(res, 400, { error: "invalid_device_token" });
      }
      if (
        !isUUID(activeAccountID) ||
        accounts.length === 0 ||
        accounts.length !== rawAccounts.length ||
        uniqueAccountIDs.size !== accounts.length ||
        !uniqueAccountIDs.has(activeAccountID)
      ) {
        return json(res, 400, { error: "invalid_account_mapping" });
      }

      const store = readStore();
      store.devices = store.devices || {};
      pruneExpiredDevices(store);
      if (!store.devices[deviceToken] && Object.keys(store.devices).length >= MAX_STORED_DEVICES) {
        return json(res, 429, { error: "device_limit_reached" });
      }
      store.devices[deviceToken] = {
        updatedAt: new Date().toISOString(),
        bundleID: sanitizedText(payload.bundleID, "com.distantg.xflow", 128),
        platform: "macos",
        activeAccountID,
        accounts
      };
      writeStore(store);

      return json(res, 200, { ok: true });
    } catch (error) {
      return json(res, error.statusCode || 400, { error: "sync_failed" });
    }
  }

  if (req.method === "POST" && req.url === "/v1/push/test") {
    if (!isAuthorized(req, ADMIN_TOKEN)) {
      return json(res, 401, { error: "unauthorized" });
    }
    try {
      const payload = await readJSON(req);
      const accountID = String(payload.accountID || "").trim();
      if (!isUUID(accountID)) {
        return json(res, 400, { error: "invalid_account_id" });
      }

      const store = readStore();
      const deviceTokens = uniqueTokensForAccount(store, accountID);
      if (deviceTokens.length === 0) {
        return json(res, 404, { error: "no_devices_for_account", accountID });
      }
      if (deviceTokens.length > MAX_PUSH_RECIPIENTS) {
        return json(res, 429, { error: "recipient_limit_exceeded" });
      }

      const title = sanitizedText(payload.title, "New X Notification", 80);
      const body = sanitizedText(payload.body, "Open Mosaic to view account activity.", 240);

      const apnsPayload = {
        aps: {
          alert: { title, body },
          sound: "default"
        },
        xflowAccountID: accountID
      };

      const results = await Promise.all(deviceTokens.map((token) => sendApns(token, apnsPayload)));
      return json(res, 200, { ok: true, accountID, sent: results });
    } catch (error) {
      return json(res, error.statusCode || 400, { error: "push_failed" });
    }
  }

  return json(res, 404, { error: "not_found" });
});

server.requestTimeout = 15_000;
server.headersTimeout = 10_000;
server.keepAliveTimeout = 5_000;

server.listen(PORT, HOST, () => {
  console.log(`xFlow push relay listening on ${HOST}:${PORT}`);
  console.log(`sync endpoint: POST http://${HOST}:${PORT}/v1/devices/sync`);
  console.log(`test endpoint: POST http://${HOST}:${PORT}/v1/push/test`);
});
