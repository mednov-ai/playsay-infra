// Browser routing for the synthetic fixture. Never fall back to the shared DEV API.
const webHosts = new Set(["dev.online.honey.school", "dev.online.honeyschool.ru"]);
const identityHost = "dev.ops.honey.school";

export function validatePorts(ports) {
  const result = {};
  for (const name of ["web", "api", "collaboration"]) {
    const value = Number(ports[name]);
    if (!Number.isInteger(value) || value < 1024 || value > 65535) throw new Error(`Invalid ${name} fixture port`);
    result[name] = value;
  }
  if (new Set(Object.values(result)).size !== 3) throw new Error("Fixture ports must be distinct");
  return result;
}

export function classify(raw, ports, websocket = false) {
  const url = new URL(raw);
  const scheme = websocket ? "wss:" : "https:";
  if (url.protocol !== scheme || url.username || url.password || url.port) throw new Error("Unexpected request origin");
  if (!websocket && url.hostname === identityHost) return { kind: "identity" };
  if (!webHosts.has(url.hostname)) throw new Error("Unexpected request host");
  if (url.pathname === "/livekit" || url.pathname.startsWith("/livekit/")) return { kind: "livekit" };
  if (websocket && url.pathname === "/collab/ws") {
    return { kind: "collaboration", target: `ws://127.0.0.1:${ports.collaboration}${url.pathname}${url.search}` };
  }
  if (url.pathname === "/api" || url.pathname.startsWith("/api/")) {
    const path = url.pathname.slice(4) || "/";
    return { kind: "api", target: `${websocket ? "ws" : "http"}://127.0.0.1:${ports.api}${path}${url.search}` };
  }
  if (websocket) throw new Error("Unexpected WebSocket path");
  return { kind: "web", target: `http://127.0.0.1:${ports.web}${url.pathname}${url.search}` };
}

export async function installIsolatedRoutes(context, inputPorts) {
  const ports = validatePorts(inputPorts);
  await context.route("**/*", async route => {
    try {
      const request = route.request();
      const decision = classify(request.url(), ports);
      if (decision.kind === "identity" || decision.kind === "livekit") return await route.continue();
      const headers = { ...request.headers(), "accept-encoding": "identity" };
      for (const name of ["host", "content-length", "transfer-encoding", "connection"]) delete headers[name];
      const method = request.method();
      const body = method === "GET" || method === "HEAD" ? undefined : request.postDataBuffer() ?? undefined;
      const response = await fetch(decision.target, { method, headers, body, redirect: "manual", signal: AbortSignal.timeout(30000) });
      const responseHeaders = Object.fromEntries(response.headers);
      for (const name of ["content-encoding", "content-length", "transfer-encoding", "connection"]) delete responseHeaders[name];
      await route.fulfill({ status: response.status, headers: responseHeaders, body: Buffer.from(await response.arrayBuffer()) });
    } catch (_) {
      await route.abort("blockedbyclient").catch(() => {});
    }
  });
  await context.routeWebSocket(/.*/, socket => {
    try {
      const decision = classify(socket.url(), ports, true);
      if (decision.kind === "livekit") { socket.connectToServer(); return; }
      const upstream = new WebSocket(decision.target, socket.protocols());
      upstream.binaryType = "arraybuffer";
      const pending = [];
      let pendingBytes = 0;
      socket.onMessage(message => {
        const size = typeof message === "string" ? Buffer.byteLength(message) : message.byteLength;
        if (size > 1024 * 1024) { socket.close({ code: 1009 }).catch(() => {}); return; }
        if (upstream.readyState === WebSocket.OPEN) upstream.send(message);
        else if (upstream.readyState === WebSocket.CONNECTING && pending.length < 64 && pendingBytes + size <= 4 * 1024 * 1024) {
          pending.push(message);
          pendingBytes += size;
        }
        else socket.close({ code: 1011 }).catch(() => {});
      });
      socket.onClose(() => upstream.close());
      upstream.onopen = () => { for (const message of pending.splice(0)) upstream.send(message); };
      upstream.onmessage = event => socket.send(typeof event.data === "string" ? event.data : Buffer.from(event.data));
      upstream.onclose = () => socket.close().catch(() => {});
      upstream.onerror = () => socket.close({ code: 1011 }).catch(() => {});
    } catch (_) {
      socket.close({ code: 1008 }).catch(() => {});
    }
  });
}
