import { execFileSync } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const platform = resolve(process.argv[2] ?? "../playsay-platform");
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const chart = resolve(root, "helm-charts/api-gateway");
const names = ["PLAYSAY_REGIONAL_RELAY_ENVIRONMENT", "PLAYSAY_REGIONAL_RELAY_MODE",
  "PLAYSAY_REGIONAL_SIGNALING_MODE", "PLAYSAY_REGIONAL_MEDIA_MODE", "PLAYSAY_REGIONAL_RELAY_SIGNALING_URL"];
const matrix = [];
for (const [scenario, file, extra, expected] of [
  ["prod", "prod", [], ["prod", "off", "rf-two-hop", "rf-turn-relay"]],
  ["dev", "dev", [], ["dev", "off", "off", "off"]],
  ["rollback", "prod", ["--set", "livekit.regionalRelay.mediaMode=off"], ["prod", "off", "rf-two-hop", "off"]],
]) {
  const rendered = execFileSync("helm", ["template", "api-gateway", chart, "-f", `${chart}/values-${file}.yaml`, ...extra], { encoding: "utf8" });
  const values = names.map(name => {
    const matches = [...rendered.matchAll(new RegExp(`- name: ${name}\\s+value: "([^"\\n]*)"`, "g"))];
    if (matches.length !== 1) throw new Error(`Missing or duplicate routing field: ${name}`);
    return matches[0][1];
  });
  if (values.slice(0, 4).some((value, index) => value !== expected[index])) throw new Error(`Unexpected ${scenario} routing policy`);
  matrix.push([scenario, ...values].join("|"));
}
execFileSync("gradle", [":api-gateway:test", "--tests", "*RegionalMediaRoutingBindingTest",
  "-PlowMemoryTests", "-Pkotlin.compiler.execution.strategy=in-process", "--no-daemon", "--max-workers=1"], {
  cwd: resolve(platform, "backend"), stdio: "inherit",
  env: { ...process.env, REGIONAL_ROUTING_HELM_MATRIX: matrix.join("\n") },
});
console.log("Candidate Helm prod/dev/rollback settings passed actual API binding tests.");
