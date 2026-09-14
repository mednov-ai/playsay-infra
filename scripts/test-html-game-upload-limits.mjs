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

const ax41Tasks = readFileSync(resolve(repositoryRoot, "ansible/roles/edge-proxy/tasks/main.yaml"), "utf8");
const rfTasks = readFileSync(resolve(repositoryRoot, "ansible/roles/rf-edge-proxy/tasks/main.yaml"), "utf8");
const rfWrapper = readFileSync(resolve(repositoryRoot, "scripts/apply-rf-edge-release.sh"), "utf8");
for (const [name, tasks] of [["AX41", ax41Tasks], ["RF edge", rfTasks]]) {
  assert.match(tasks, /tags: html-game-upload-routes/);
  assert.match(tasks, /insertafter: '\^    server_name online\\\.(?:honey\\\.school|honeyschool\\\.ru);\$'/);
  assert.match(tasks, /client_max_body_size 21m;/);
  assert.match(tasks, /cmd: nginx -t/);
  assert.match(tasks, /ansible\.builtin\.meta: flush_handlers/);
  assert.doesNotMatch(tasks, /html-game-upload-routes[\s\S]{0,250}(?:ufw|coturn|landing)/i, `${name} emergency tag must remain route-only`);
}
assert.match(rfWrapper, /--html-game-upload-only/);
assert.match(rfWrapper, /--tags html-game-upload-routes/);
assert.match(
  ax41Tasks,
  /split\('server_name online\.honey\.school;'\)\)\[2\][\s\S]*split\('server_name dev\.online\.honey\.school;'\)\[0\]/,
  "AX41 emergency reconciliation must inspect the production server block instead of accepting the dev route",
);

console.log("AX41 and RF-edge HTML-game upload limit contracts passed");
