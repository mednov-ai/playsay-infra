import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { once } from "node:events";
import http from "node:http";
import { createRequire } from "node:module";
import { homedir } from "node:os";
import path from "node:path";
import test from "node:test";
import { installIsolatedRoutes } from "./router.mjs";

const playwrightDir = process.env.PLAYWRIGHT_PACKAGE_DIR ?? path.join(homedir(), ".codex/tools/playwright");
const { chromium } = createRequire(path.join(playwrightDir, "package.json"))("playwright");

async function listen(server) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return server.address().port;
}

test("a browser uses only the fixture for app HTTP and collaboration WebSocket", async () => {
  const web = http.createServer((_req, res) => { res.writeHead(200, { "content-type": "text/html" }); res.end("<!doctype html><title>isolated fixture</title>"); });
  let apiAuthorizationVerified = false;
  const api = http.createServer((req, res) => { apiAuthorizationVerified = req.headers.authorization === "Bearer synthetic-test-token"; res.writeHead(200, { "content-type": "application/json" }); res.end('{"fixture":true}'); });
  const collab = http.createServer();
  let peer;
  let apiPeer;
  let apiProtocolVerified = false;
  api.on("upgrade", (req, connection) => {
    apiPeer = connection;
    assert.equal(req.url, "/ws/chat");
    assert.equal(req.headers.origin, "https://dev.online.honey.school");
    assert.deepEqual(req.headers["sec-websocket-protocol"].split(",").map(value => value.trim()), ["playsay", "fixture-token"]);
    apiProtocolVerified = true;
    const accept = createHash("sha1").update(req.headers["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
    connection.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\nSec-WebSocket-Protocol: playsay\r\n\r\n`);
    connection.once("data", frame => {
      const length = frame[1] & 0x7f;
      if (length >= 126 || !(frame[1] & 0x80)) { connection.destroy(); return; }
      const mask = frame.subarray(2, 6);
      const payload = Buffer.from(frame.subarray(6, 6 + length));
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
      connection.write(Buffer.concat([Buffer.from([0x81, payload.length]), payload]));
    });
  });
  collab.on("upgrade", (req, connection) => {
    assert.equal(req.headers.origin, "https://dev.online.honey.school");
    peer = connection;
    const accept = createHash("sha1").update(req.headers["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
    connection.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    connection.once("data", frame => {
      const length = frame[1] & 0x7f;
      if (length >= 126 || !(frame[1] & 0x80)) { connection.destroy(); return; }
      const mask = frame.subarray(2, 6);
      const payload = Buffer.from(frame.subarray(6, 6 + length));
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
      connection.write(Buffer.concat([Buffer.from([0x81, payload.length]), payload]));
    });
  });
  const ports = { web: await listen(web), api: await listen(api), collaboration: await listen(collab) };
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({ serviceWorkers: "block" });
    await installIsolatedRoutes(context, ports);
    const page = await context.newPage();
    await page.goto("https://dev.online.honey.school/", { waitUntil: "domcontentloaded" });
    assert.equal(await page.title(), "isolated fixture");
    assert.equal(await page.evaluate(async () => (await (await fetch("/api/fixture", { headers: { Authorization: "Bearer synthetic-test-token" } })).json()).fixture), true);
    assert.equal(apiAuthorizationVerified, true);
    assert.equal(await page.evaluate(async () => {
      try { await fetch("https://online.honey.school/api/fixture"); return false; } catch (_) { return true; }
    }), true);
    assert.equal(await page.evaluate(() => new Promise((resolve, reject) => {
      const socket = new WebSocket("wss://dev.online.honey.school/collab/ws?fixture=1");
      const timer = setTimeout(() => reject(new Error("fixture WebSocket timeout")), 5000);
      socket.onopen = () => socket.send("synthetic");
      socket.onerror = () => reject(new Error("fixture WebSocket failed"));
      socket.onmessage = event => { clearTimeout(timer); socket.close(); resolve(event.data); };
    })), "synthetic");
    assert.equal(await page.evaluate(() => new Promise((resolve, reject) => {
      const socket = new WebSocket("wss://dev.online.honey.school/api/ws/chat", ["playsay", "fixture-token"]);
      const timer = setTimeout(() => reject(new Error("fixture API WebSocket timeout")), 5000);
      socket.onopen = () => socket.send("synthetic-api");
      socket.onerror = () => reject(new Error("fixture API WebSocket failed"));
      socket.onmessage = event => { clearTimeout(timer); socket.close(); resolve(event.data); };
    })), "synthetic-api");
    assert.equal(apiProtocolVerified, true);
    await context.close();
  } finally {
    peer?.destroy();
    apiPeer?.destroy();
    await browser.close();
    for (const server of [web, api, collab]) { server.closeAllConnections(); server.close(); }
  }
});
