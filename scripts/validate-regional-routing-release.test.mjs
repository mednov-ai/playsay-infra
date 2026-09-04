import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
import test from "node:test";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
test("routing gate rejects old source, silent media loss and missing baseline", () => {
  const temp = mkdtempSync(resolve(tmpdir(), "routing-gate-test-"));
  const write = (path, value) => { mkdirSync(dirname(resolve(temp, path)), { recursive: true }); writeFileSync(resolve(temp, path), value); };
  const values = media => `livekit:\n  regionalRelay:\n    signalingMode: rf-two-hop\n    mediaMode: ${media}\n`;
  try {
    write("scripts/placeholder", "");
    copyFileSync(resolve(root, "scripts/validate-regional-routing-release.sh"), resolve(temp, "scripts/guard.sh"));
    write("helm-charts/api-gateway/values-prod.yaml", values("rf-turn-relay"));
    const git = (...args) => execFileSync("git", args, { cwd: temp, stdio: "pipe" });
    git("init", "-q"); git("add", ".");
    git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "test fixture only");
    const run = (base = "HEAD", extra = []) => spawnSync("sh", ["scripts/guard.sh", temp, "WORKTREE", base, ...extra], { cwd: temp, encoding: "utf8" });
    const config = "backend/api-gateway/src/main/resources/application.yaml";
    write(config, "regional-relay:\n  mode: off\n");
    assert.notEqual(run().status, 0);
    write(config, 'signaling-mode: ${PLAYSAY_REGIONAL_SIGNALING_MODE:}\nmedia-mode: ${PLAYSAY_REGIONAL_MEDIA_MODE:}\n');
    assert.notEqual(run().status, 0);
    write("backend/api-gateway/src/test/kotlin/com/playsay/gateway/service/RegionalMediaRoutingBindingTest.kt", "fixture");
    assert.equal(run().status, 0);
    write("helm-charts/api-gateway/values-prod.yaml", values("off"));
    assert.notEqual(run().status, 0);
    assert.equal(run("HEAD", ["--media-rollback"]).status, 0);
    assert.notEqual(run("missing-baseline").status, 0);
    write("helm-charts/api-gateway/values-prod.yaml", values("rf-turn-relay").replace("rf-two-hop", "off"));
    assert.notEqual(run().status, 0);
  } finally { rmSync(temp, { recursive: true, force: true }); }
});
