import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('..',import.meta.url));
function render(values=[]) {return spawnSync('helm',['template','games','helm-charts/api-gateway',...values.flatMap(v=>['--set',v])],{cwd:root,encoding:'utf8'});}
const digest='sha256:'+'1'.repeat(64);
assert.equal(render().status,0);assert.doesNotMatch(render().stdout,/kind: Job/);
const dry=render(['games.migration.enabled=true',`image.digest=${digest}`]);assert.equal(dry.status,0,dry.stderr);assert.match(dry.stdout,/kind: Job/);assert.match(dry.stdout,/--playsay.scheduling.enabled=false/);assert.match(dry.stdout,/backoffLimit: 0/);assert.match(dry.stdout,/restartPolicy: Never/);assert.match(dry.stdout,/-Xmx384m/);
const customRuntime=render(['games.migration.enabled=true',`image.digest=${digest}`,'runtime.javaToolOptions=-Xmx2g']);assert.equal(customRuntime.status,0,customRuntime.stderr);const jobManifest=customRuntime.stdout.split('kind: Job')[1];assert.match(jobManifest,/-Xmx384m/);assert.doesNotMatch(jobManifest,/-Xmx2g/);
assert.notEqual(render(['games.migration.enabled=true']).status,0);
assert.notEqual(render(['games.migration.enabled=true','games.migration.dryRun=false',`image.digest=${digest}`]).status,0);
const safe=['games.migration.enabled=true','games.migration.dryRun=false','games.migration.drained=true','games.maintenance=true','games.writesEnabled=false',`image.digest=${digest}`];
const apply=render(safe);assert.equal(apply.status,0,apply.stderr);assert.match(apply.stdout,/--playsay.games.migration.drained=true/);assert.match(apply.stdout,/PLAYSAY_GAMES_MAINTENANCE/);
assert.notEqual(render([...safe,'games.migration.runId=INVALID']).status,0);
console.log('Game library migration render and fail-closed guards passed');
