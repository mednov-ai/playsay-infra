import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import http from "node:http";
import { once } from "node:events";
import test from "node:test";
import { classify, installIsolatedRoutes, validatePorts } from "./router.mjs";

const ports = { web: 30001, api: 30002, collaboration: 30003 };

test("routing only permits DEV identity and media, and maps application traffic to loopback", () => {
  assert.equal(classify("https://dev.ops.honey.school/keycloak/", ports).kind, "identity");
  assert.equal(classify("wss://dev.online.honeyschool.ru/livekit/rtc", ports, true).kind, "livekit");
  assert.deepEqual(classify("https://dev.online.honey.school/api/lessons?test=1", ports), {
    kind: "api", target: "http://127.0.0.1:30002/lessons?test=1",
  });
  assert.equal(classify("https://dev.online.honey.school/assets/app.js", ports).target, "http://127.0.0.1:30001/assets/app.js");
  assert.equal(classify("wss://dev.online.honeyschool.ru/collab/ws?fixture=1", ports, true).target, "ws://127.0.0.1:30003/collab/ws?fixture=1");
  assert.throws(() => classify("https://online.honey.school/api/lessons", ports));
  assert.throws(() => classify("https://dev.online.honey.school.example.test/api", ports));
  assert.throws(() => classify("wss://dev.online.honey.school/unknown", ports, true));
  assert.throws(() => validatePorts({ ...ports, api: ports.web }));
});

test("an API request reaches only the selected loopback fixture and an unknown host is blocked", async () => {
  const server = http.createServer((req, res) => { res.writeHead(200, { "content-type": "application/json" }); res.end(JSON.stringify({ path: req.url })); });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const api = server.address().port;
  const used = new Set([api]);
  const spare = () => { for (let p = 30001; p < 60000; p++) if (!used.has(p)) { used.add(p); return p; } throw new Error("No test port"); };
  const fixturePorts = { api, web: spare(), collaboration: spare() };
  let handler;
  const context = { route: async (_pattern, fn) => { handler = fn; }, routeWebSocket: async () => {} };
  try {
    await installIsolatedRoutes(context, fixturePorts);
    let response;
    const request = url => ({ url: () => url, method: () => "GET", headers: () => ({}), postDataBuffer: () => null });
    await handler({ request: () => request("https://dev.online.honey.school/api/fixture?sample=1"), fulfill: async value => { response = value; }, continue: async () => { throw new Error("unexpected network fallback"); }, abort: async () => { throw new Error("unexpected abort"); } });
    assert.equal(response.status, 200);
    assert.deepEqual(JSON.parse(response.body.toString()), { path: "/fixture?sample=1" });
    let blocked = false;
    await handler({ request: () => request("https://online.honey.school/api/fixture"), continue: async () => { throw new Error("production fallback"); }, abort: async () => { blocked = true; } });
    assert.equal(blocked, true);
  } finally {
    server.close();
    await once(server, "close");
  }
});

test("collaboration WebSocket messages are bridged to loopback", async () => {
  const server = http.createServer();
  let peer;
  server.on("upgrade", (req, connection) => {
    peer = connection;
    const accept = createHash("sha1").update(req.headers["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
    connection.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    connection.once("data", frame => {
      const length = frame[1] & 0x7f;
      assert.ok(length < 126 && (frame[1] & 0x80));
      const mask = frame.subarray(2, 6);
      const payload = Buffer.from(frame.subarray(6, 6 + length));
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
      connection.write(Buffer.concat([Buffer.from([0x81, payload.length]), payload]));
    });
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const collaboration = server.address().port;
  const used = new Set([collaboration]);
  const spare = () => { for (let p = 30001; p < 60000; p++) if (!used.has(p)) { used.add(p); return p; } throw new Error("No test port"); };
  let handler;
  const context = { route: async () => {}, routeWebSocket: async (_pattern, fn) => { handler = fn; } };
  let onMessage;
  let onClose;
  let receive;
  const response = new Promise(resolve => { receive = resolve; });
  const socket = {
    url: () => "wss://dev.online.honey.school/collab/ws?fixture=1",
    protocols: () => [], onMessage: fn => { onMessage = fn; }, onClose: fn => { onClose = fn; },
    send: value => receive(value), close: async () => {},
  };
  try {
    await installIsolatedRoutes(context, { collaboration, api: spare(), web: spare() });
    handler(socket);
    onMessage("synthetic");
    assert.equal(await Promise.race([response, new Promise((_, reject) => setTimeout(() => reject(new Error("WebSocket bridge timed out")), 3000).unref())]), "synthetic");
    onClose();
  } finally {
    peer?.destroy();
    server.closeAllConnections();
    server.close();
  }
});
