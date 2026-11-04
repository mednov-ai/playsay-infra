"""Create an isolated copy of the existing task-owned DEV group smoke script."""

import argparse
import json
from pathlib import Path


def replace_once(content, old, new):
    if content.count(old) != 1:
        raise ValueError("Unexpected source shape; refusing to prepare a smoke script")
    return content.replace(old, new, 1)


def prepare(source, output):
    source = source.resolve(strict=True)
    output = output.resolve()
    if source == output or output.exists():
        raise ValueError("Output must be a new task-owned file")
    router = Path(__file__).resolve().with_name("router.mjs").as_uri()
    content = source.read_text()
    content = replace_once(
        content,
        'import path from "node:path";\n',
        'import path from "node:path";\nimport { installIsolatedRoutes, validatePorts } from ' + json.dumps(router) + ';\n',
    )
    anchor = 'const authClientId = process.env.PLAY_SAY_SMOKE_AUTH_CLIENT_ID ?? "playsay-web";\n'
    guarded = anchor + '''const fixturePorts = validatePorts({
  api: process.env.STACK_ACCEPTANCE_API_PORT,
  web: process.env.STACK_ACCEPTANCE_WEB_PORT,
  collaboration: process.env.STACK_ACCEPTANCE_COLLAB_PORT,
});
const fixtureApi = new URL(apiBaseUrl);
if (fixtureApi.protocol !== "http:" || fixtureApi.hostname !== "127.0.0.1" ||
    fixtureApi.port !== String(fixturePorts.api) || fixtureApi.pathname !== "/" || fixtureApi.search || fixtureApi.hash) {
  throw new Error("The smoke API must be the isolated loopback fixture");
}
const fixtureWeb = new URL(webBaseUrl);
if (fixtureWeb.protocol !== "https:" || fixtureWeb.port ||
    !new Set(["dev.online.honey.school", "dev.online.honeyschool.ru"]).has(fixtureWeb.hostname) ||
    authIssuer !== "https://dev.ops.honey.school/keycloak/realms/playsay" || authClientId !== "playsay-web") {
  throw new Error("The smoke requires the fixed DEV web and identity endpoints");
}
'''
    content = replace_once(content, anchor, guarded)
    content = replace_once(
        content,
        '  const context = await nextBrowser.newContext({\n    ignoreHTTPSErrors: false,',
        '  const context = await nextBrowser.newContext({\n    serviceWorkers: "block",\n    ignoreHTTPSErrors: false,',
    )
    content = replace_once(
        content,
        '  if (fakeMedia) {\n    await context.grantPermissions',
        '  await installIsolatedRoutes(context, fixturePorts);\n  if (fakeMedia) {\n    await context.grantPermissions',
    )
    content = replace_once(
        content,
        'const sshJumpHost = process.env.PLAY_SAY_SMOKE_SSH_JUMP_HOST ?? "root@65.109.55.110";\n',
        'const sshJumpHost = process.env.PLAY_SAY_SMOKE_SSH_JUMP_HOST ?? "root@65.109.55.110";\n'
        'if (sshHost !== "playsay@10.60.0.30" || sshJumpHost !== "root@65.109.55.110") throw new Error("The smoke SSH route must be DEV-only");\n',
    )
    content = replace_once(
        content,
        '  const formUrl = new URL(form.action);\n',
        '  const formUrl = new URL(form.action);\n'
        '  if (formUrl.origin !== new URL(authIssuer).origin || !formUrl.pathname.startsWith("/keycloak/realms/playsay/")) throw new Error("Unexpected DEV identity login form");\n',
    )
    output.write_text(content, encoding="utf-8", errors="strict")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    prepare(args.source, args.output)
