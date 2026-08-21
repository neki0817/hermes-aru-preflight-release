import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  DOWNLOAD_STAGE_ENVIRONMENT_GUARD,
  RELEASE_SCHEMA_VERSION,
  SOURCE_SPECS,
  STAGE_NAMESPACE,
  renderAruReadOnlyPreflightDownloadStage,
  serializeReleaseManifest,
} from "../tools/discord-cody-aru-direct-bridge/generate-aru-read-only-preflight-download-stage.mjs";

const checkoutRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const toolsRoot = resolve(checkoutRoot, "tools/discord-cody-aru-direct-bridge");
const artifactName = "AruReadOnlyPreflightStage.download-only.sh";
const sidecarName = `${artifactName}.sha256`;

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function extractBase64Payload(script, marker) {
  const expression = new RegExp(`<<'${marker}'\\n([A-Za-z0-9+/=\\n]+)\\n${marker}\\n`, "u");
  const match = expression.exec(script);
  assert.ok(match, `missing ${marker} payload`);
  return Buffer.from(match[1].replace(/\\s/gu, ""), "base64");
}

function withoutEmbeddedPayloads(script) {
  return script.replace(/<<'__HERMES_ARU_DOWNLOAD_(?:LIBRARY|RUNNER)_BASE64__'\n[A-Za-z0-9+/=\n]+\n__HERMES_ARU_DOWNLOAD_(?:LIBRARY|RUNNER)_BASE64__\n/gu, "");
}

test("download-only artifact is deterministic and pins the exact current two-source release", async () => {
  const generated = await renderAruReadOnlyPreflightDownloadStage(checkoutRoot);
  const [artifact, sidecar] = await Promise.all([
    readFile(resolve(toolsRoot, artifactName), "utf8"),
    readFile(resolve(toolsRoot, sidecarName), "utf8"),
  ]);
  const expectedEntries = await Promise.all(SOURCE_SPECS.map(async (spec) => {
    const bytes = await readFile(resolve(checkoutRoot, spec.releasePath));
    return { ...spec, bytes, size: bytes.byteLength, sha256: sha256(bytes) };
  }));

  assert.equal(artifact, generated.script);
  assert.equal(sha256(Buffer.from(artifact, "utf8")), generated.sha256);
  assert.equal(Buffer.byteLength(artifact, "utf8"), generated.size);
  assert.equal(sidecar, `${generated.sha256}  ${artifactName}\n`);
  assert.equal(generated.releaseDigest, sha256(serializeReleaseManifest(expectedEntries)));
  assert.equal(RELEASE_SCHEMA_VERSION, "hermes-agents-discord-cody-aru-aru-preflight-release/v1");

  const library = extractBase64Payload(artifact, "__HERMES_ARU_DOWNLOAD_LIBRARY_BASE64__");
  const runner = extractBase64Payload(artifact, "__HERMES_ARU_DOWNLOAD_RUNNER_BASE64__");
  assert.deepEqual(library, expectedEntries.find((entry) => entry.role === "library").bytes);
  assert.deepEqual(runner, expectedEntries.find((entry) => entry.role === "runner").bytes);
  for (const expected of expectedEntries) {
    const actual = expected.role === "library" ? library : runner;
    assert.equal(actual.byteLength, expected.size);
    assert.equal(sha256(actual), expected.sha256);
  }
});

test("download-only artifact is guarded staging code, not a transport command or an executable preflight", async () => {
  const { script } = await renderAruReadOnlyPreflightDownloadStage(checkoutRoot);
  const outer = withoutEmbeddedPayloads(script);

  assert.match(outer, /^#!\/bin\/sh$/mu);
  assert.match(outer, /DOWNLOAD-ONLY: do not paste this file into the serial console/u);
  assert.match(outer, new RegExp(`\\[ "\\$\\{${DOWNLOAD_STAGE_ENVIRONMENT_GUARD}:-\\}" = 1 \\] \\|\\| stage_failure`, "u"));
  assert.match(outer, /LC_ALL=C\nexport LC_ALL/u);
  assert.ok(outer.includes(`STAGE_NAMESPACE='${STAGE_NAMESPACE}'`));
  assert.match(outer, /create_fresh_private_directory "\$STAGE_NAMESPACE"/u);
  assert.match(outer, /\/usr\/bin\/base64 --decode > "\$LIBRARY_PATH"/u);
  assert.match(outer, /\/usr\/bin\/base64 --decode > "\$RUNNER_PATH"/u);
  assert.match(outer, /\/usr\/bin\/chmod 0400 -- "\$LIBRARY_PATH" "\$RUNNER_PATH"/u);
  assert.match(outer, /network_request_count":0/u);
  assert.match(outer, /message_send_attempt_count":0/u);
  assert.doesNotMatch(outer, /\b(?:curl|wget|ssh|git|node|npm|apt|rm|rmdir|mv)\b/iu);
  assert.doesNotMatch(outer, /https?:\/\//iu);
  assert.doesNotMatch(outer, /(?:DISCORD_BOT_TOKEN|authorization|bearer)/iu);
  assert.doesNotMatch(outer, /(?:exec|\. )\s+[^\n]*(?:LIBRARY_PATH|RUNNER_PATH)/u);
});
