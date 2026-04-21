#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import http2 from "node:http2";
import path from "node:path";

const PORT = Number(process.env.PORT || 8787);
const MAP_PATH = process.env.XFLOW_DEVICE_MAP_PATH || path.resolve("dist/push-device-map.json");

const APNS_ENV = process.env.APNS_ENV || "development";
const APNS_HOST = APNS_ENV === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
const APNS_KEY_ID = process.env.APNS_KEY_ID || "";
const APNS_TEAM_ID = process.env.APNS_TEAM_ID || "";
const APNS_BUNDLE_ID = process.env.APNS_BUNDLE_ID || "";
const APNS_AUTH_KEY_PATH = process.env.APNS_AUTH_KEY_PATH || "";

function ensureStoreFile() {
  fs.mkdirSync(path.dirname(MAP_PATH), { recursive: true });
  if (!fs.existsSync(MAP_PATH)) {
    fs.writeFileSync(MAP_PATH, JSON.stringify({ devices: {} }, null, 2));
  }
}

function readStore() {
  ensureStoreFile();
  try {
    return JSON.parse(fs.readFileSync(MAP_PATH, "utf8"));
  } catch {
    return { devices: {} };
  }
}

function writeStore(data) {
  ensureStoreFile();
  fs.writeFileSync(MAP_PATH, JSON.stringify(data, null, 2));
}

function json(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

function readJSON(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
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

  const signature = crypto.createSign("sha256").update(message).end().sign(privateKey);
  return `${message}.${base64url(signature)}`;
}

function sendApns(token, payload) {
  if (!APNS_BUNDLE_ID) {
    return Promise.resolve({ token, ok: false, status: 0, error: "Missing APNS_BUNDLE_ID" });
  }

  let jwt;
  try {
    jwt = createJwt();
  } catch (error) {
    return Promise.resolve({ token, ok: false, status: 0, error: String(error.message || error) });
  }

  return new Promise((resolve) => {
    const client = http2.connect(APNS_HOST);
    client.on("error", (error) => {
      resolve({ token, ok: false, status: 0, error: error.message });
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
        token,
        ok: statusCode >= 200 && statusCode < 300,
        status: statusCode,
        body: body || undefined
      });
    });
    request.on("error", (error) => {
      client.close();
      resolve({ token, ok: false, status: statusCode, error: error.message });
    });

    request.end(JSON.stringify(payload));
  });
}

function uniqueTokensForAccount(store, accountID) {
  const tokens = [];
  for (const [token, entry] of Object.entries(store.devices || {})) {
    const accounts = Array.isArray(entry.accounts) ? entry.accounts : [];
    if (accounts.some((account) => account?.id === accountID)) {
      tokens.push(token);
    }
  }
  return [...new Set(tokens)];
}

const server = http.createServer(async (req, res) => {
  if (!req.url) {
    return json(res, 404, { error: "not_found" });
  }

  if (req.method === "GET" && req.url === "/health") {
    return json(res, 200, { ok: true, apnsEnv: APNS_ENV, mapPath: MAP_PATH });
  }

  if (req.method === "POST" && req.url === "/v1/devices/sync") {
    try {
      const payload = await readJSON(req);
      const deviceToken = String(payload.deviceToken || "").trim();
      if (!deviceToken) {
        return json(res, 400, { error: "deviceToken_required" });
      }

      const store = readStore();
      store.devices = store.devices || {};
      store.devices[deviceToken] = {
        updatedAt: new Date().toISOString(),
        bundleID: payload.bundleID || "",
        platform: payload.platform || "macos",
        activeAccountID: payload.activeAccountID || null,
        accounts: Array.isArray(payload.accounts) ? payload.accounts : []
      };
      writeStore(store);

      return json(res, 200, { ok: true });
    } catch (error) {
      return json(res, 500, { error: "sync_failed", message: String(error.message || error) });
    }
  }

  if (req.method === "POST" && req.url === "/v1/push/test") {
    try {
      const payload = await readJSON(req);
      const accountID = String(payload.accountID || "").trim();
      if (!accountID) {
        return json(res, 400, { error: "accountID_required" });
      }

      const store = readStore();
      const deviceTokens = uniqueTokensForAccount(store, accountID);
      if (deviceTokens.length === 0) {
        return json(res, 404, { error: "no_devices_for_account", accountID });
      }

      const title = String(payload.title || "New X Notification");
      const body = String(payload.body || "Open xFlow to view account activity.");

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
      return json(res, 500, { error: "push_failed", message: String(error.message || error) });
    }
  }

  return json(res, 404, { error: "not_found" });
});

server.listen(PORT, () => {
  console.log(`xFlow push relay listening on :${PORT}`);
  console.log(`sync endpoint: POST http://localhost:${PORT}/v1/devices/sync`);
  console.log(`test endpoint: POST http://localhost:${PORT}/v1/push/test`);
});
