import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const repositoryRoot = resolve(import.meta.dirname, "..");
const cases = [
  ["AX41", "ansible/roles/edge-proxy/templates/playsay-honey.conf.j2", 1, 2],
  ["RF edge", "ansible/roles/rf-edge-proxy/templates/playsay-honey-rf-edge.conf.j2", 1, 2],
];

for (const [name, relativePath, expectedLimits, expectedInvocations] of cases) {
  const template = readFileSync(resolve(repositoryRoot, relativePath), "utf8");
  assert.match(template, /materials\/\[\^\/\]\+\/assets\/html-games/);
  assert.match(template, /schedule\/lessons\/\[\^\/\]\+\/html-game-page/);
  assert.equal((template.match(/client_max_body_size 21m;/g) ?? []).length, expectedLimits, `${name} must define one scoped 21m ceiling`);
  assert.equal((template.match(/html_game_upload_locations\(route, '(?:http|https)'\)/g) ?? []).length, expectedInvocations, `${name} must render the ceiling for HTTP bootstrap and HTTPS`);
  assert.doesNotMatch(template, /location \/ \{\s*client_max_body_size 21m;/);
}

console.log("AX41 and RF-edge HTML-game upload limit contracts passed");
