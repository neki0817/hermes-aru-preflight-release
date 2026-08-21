// Generates the full, download-only Aru staging payload.  This is not a
// serial-console paste artifact: a short SHA-256-verified transport command
// must set HERMES_ARU_DOWNLOAD_STAGE=1 before the shell will proceed.

import { createHash } from "node:crypto";
import { lstat, readFile } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const OPERATION = "aru_discord_read_only_preflight_download_stage";
export const DOWNLOAD_STAGE_ENVIRONMENT_GUARD = "HERMES_ARU_DOWNLOAD_STAGE";
export const RELEASE_SCHEMA_VERSION = "hermes-agents-discord-cody-aru-aru-preflight-release/v1";
export const STAGE_NAMESPACE = "/root/.hermes-cody-aru-preflight";

const SOURCE_SPECS = Object.freeze([
  Object.freeze({
    role: "library",
    releasePath: "services/orchestrator/src/discord-cody-aru-direct-bridge/owned-discord-aru-preflight.mjs",
  }),
  Object.freeze({
    role: "runner",
    releasePath: "services/orchestrator/src/run-discord-cody-aru-direct-bridge-aru-preflight.mjs",
  }),
]);

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function reject() {
  throw new Error("download stage source rejected");
}

function sourceCheckoutRoot() {
  return resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
}

function fixedSourcePath(checkoutRoot, releasePath) {
  const root = resolve(checkoutRoot);
  const candidate = resolve(root, releasePath);
  const relativePath = relative(root, candidate);
  if (relativePath === "" || relativePath.startsWith(`..${sep}`)) reject();
  return candidate;
}

async function readExactSource(checkoutRoot, spec) {
  const sourcePath = fixedSourcePath(checkoutRoot, spec.releasePath);
  const metadata = await lstat(sourcePath);
  if (!metadata.isFile() || metadata.isSymbolicLink() || metadata.size < 1 || metadata.size > 128 * 1024) reject();
  const bytes = await readFile(sourcePath);
  if (bytes.byteLength !== metadata.size) reject();
  return Object.freeze({ ...spec, bytes, size: bytes.byteLength, sha256: sha256(bytes) });
}

export function serializeReleaseManifest(entries) {
  return Buffer.from(JSON.stringify({
    schema_version: RELEASE_SCHEMA_VERSION,
    files: entries.map((entry) => ({ path: entry.releasePath, sha256: entry.sha256 })),
  }), "utf8");
}

function shellQuoted(value) {
  if (typeof value !== "string" || /[^A-Za-z0-9._\/-]/u.test(value)) reject();
  return `'${value}'`;
}

function base64Lines(bytes) {
  return Buffer.from(bytes).toString("base64").replace(/.{1,76}/gu, "$&\n").trimEnd();
}

function renderDownloadStage(entries) {
  if (!Array.isArray(entries) || entries.length !== 2) reject();
  const [library, runner] = entries;
  if (
    library.role !== "library"
    || runner.role !== "runner"
    || !/^[a-f0-9]{64}$/u.test(library.sha256)
    || !/^[a-f0-9]{64}$/u.test(runner.sha256)
  ) reject();

  const releaseDigest = sha256(serializeReleaseManifest(entries));
  const libraryBase64 = base64Lines(library.bytes);
  const runnerBase64 = base64Lines(runner.bytes);

  return `#!/bin/sh
# DOWNLOAD-ONLY: do not paste this file into the serial console. The short
# transport command must verify this file SHA-256 and set its guard variable.
(
set -eu
umask 077
PATH=/usr/bin:/bin
export PATH
LC_ALL=C
export LC_ALL
exec 2>/dev/null

stage_result_emitted=0
stage_failure() {
  if [ "$stage_result_emitted" -eq 0 ]; then
    stage_result_emitted=1
    printf '%s\\n' '{"ok":false,"operation":"${OPERATION}","error_code":"ARU_DISCORD_PREFLIGHT_DOWNLOAD_STAGE_REJECTED","sensitive_output_count":0}'
  fi
  trap - 0
  exit 2
}
trap 'if [ "$stage_result_emitted" -eq 0 ]; then stage_result_emitted=1; printf "%s\\n" "{\\"ok\\":false,\\"operation\\":\\"${OPERATION}\\",\\"error_code\\":\\"ARU_DISCORD_PREFLIGHT_DOWNLOAD_STAGE_REJECTED\\",\\"sensitive_output_count\\":0}"; fi' 0

assert_private_directory() {
  [ ! -L "$1" ] || stage_failure
  [ -d "$1" ] || stage_failure
  [ "$(/usr/bin/stat -c '%F:%u:%a' -- "$1")" = 'directory:0:700' ] || stage_failure
}

 create_fresh_private_directory() {
  [ ! -L "$1" ] || stage_failure
  [ ! -e "$1" ] || stage_failure
  /usr/bin/mkdir -m 700 -- "$1" || stage_failure
  assert_private_directory "$1"
}

 assert_private_regular_file() {
  [ ! -L "$1" ] || stage_failure
  [ "$(/usr/bin/stat -c '%F:%u:%a:%s' -- "$1")" = "regular file:0:400:$3" ] || stage_failure
  [ "$(/usr/bin/stat -c '%h' -- "$1")" = 1 ] || stage_failure
  stage_actual_hash=$(/usr/bin/sha256sum -- "$1" | /usr/bin/cut -d ' ' -f 1) || stage_failure
   [ "$stage_actual_hash" = "$2" ] || stage_failure
 }

 assert_nonwritable_anchor_directory() {
   [ ! -L "$1" ] || stage_failure
   [ -d "$1" ] || stage_failure
   stage_anchor=$(/usr/bin/stat -c '%F:%u:%a' -- "$1") || stage_failure
   case "$stage_anchor" in
     directory:0:7[0145][0145]) ;;
     *) stage_failure ;;
   esac
 }

 [ "$#" -eq 0 ] || stage_failure
 [ "\${${DOWNLOAD_STAGE_ENVIRONMENT_GUARD}:-}" = 1 ] || stage_failure
 [ "$(/usr/bin/id -u)" = 0 ] || stage_failure
 assert_nonwritable_anchor_directory /
 assert_nonwritable_anchor_directory /root

STAGE_NAMESPACE=${shellQuoted(STAGE_NAMESPACE)}
RUNTIME_ROOT="$STAGE_NAMESPACE/runtime"
RELEASES_ROOT="$STAGE_NAMESPACE/releases"
RELEASE_MANIFEST_SHA256=${shellQuoted(releaseDigest)}
RELEASE_ROOT="$RELEASES_ROOT/$RELEASE_MANIFEST_SHA256"
SOURCE_ROOT="$RELEASE_ROOT/services/orchestrator/src"
LIBRARY_PATH="$SOURCE_ROOT/discord-cody-aru-direct-bridge/owned-discord-aru-preflight.mjs"
RUNNER_PATH="$SOURCE_ROOT/run-discord-cody-aru-direct-bridge-aru-preflight.mjs"
LIBRARY_SHA256=${shellQuoted(library.sha256)}
RUNNER_SHA256=${shellQuoted(runner.sha256)}
LIBRARY_SIZE=${library.size}
RUNNER_SIZE=${runner.size}

 create_fresh_private_directory "$STAGE_NAMESPACE"
 assert_nonwritable_anchor_directory /
 assert_nonwritable_anchor_directory /root
 assert_private_directory "$STAGE_NAMESPACE"
 create_fresh_private_directory "$RUNTIME_ROOT"
create_fresh_private_directory "$RELEASES_ROOT"
create_fresh_private_directory "$RELEASE_ROOT"
create_fresh_private_directory "$RELEASE_ROOT/services"
create_fresh_private_directory "$RELEASE_ROOT/services/orchestrator"
create_fresh_private_directory "$SOURCE_ROOT"
create_fresh_private_directory "$SOURCE_ROOT/discord-cody-aru-direct-bridge"

if ! /usr/bin/base64 --decode > "$LIBRARY_PATH" <<'__HERMES_ARU_DOWNLOAD_LIBRARY_BASE64__'
${libraryBase64}
__HERMES_ARU_DOWNLOAD_LIBRARY_BASE64__
then
  stage_failure
fi

if ! /usr/bin/base64 --decode > "$RUNNER_PATH" <<'__HERMES_ARU_DOWNLOAD_RUNNER_BASE64__'
${runnerBase64}
__HERMES_ARU_DOWNLOAD_RUNNER_BASE64__
then
  stage_failure
fi

[ "$(/usr/bin/find "$RELEASE_ROOT" -xdev -type d -print | /usr/bin/wc -l)" -eq 5 ] || stage_failure
[ "$(/usr/bin/find "$RELEASE_ROOT" -xdev -type f -print | /usr/bin/wc -l)" -eq 2 ] || stage_failure
[ -z "$(/usr/bin/find "$RELEASE_ROOT" -xdev -type l -print -quit)" ] || stage_failure
[ -z "$(/usr/bin/find "$RELEASE_ROOT" -xdev ! -type d ! -type f -print -quit)" ] || stage_failure
[ -z "$(/usr/bin/find "$RUNTIME_ROOT" -xdev -mindepth 1 -print -quit)" ] || stage_failure

/usr/bin/chmod 0400 -- "$LIBRARY_PATH" "$RUNNER_PATH" || stage_failure
assert_private_regular_file "$LIBRARY_PATH" "$LIBRARY_SHA256" "$LIBRARY_SIZE"
assert_private_regular_file "$RUNNER_PATH" "$RUNNER_SHA256" "$RUNNER_SIZE"
/usr/bin/sync -f "$LIBRARY_PATH" "$RUNNER_PATH" "$RELEASE_ROOT" "$RUNTIME_ROOT" || stage_failure

stage_result_emitted=1
trap - 0
printf '%s\\n' '{"ok":true,"operation":"${OPERATION}","terminal_state":"staged","staged_regular_file_count":2,"network_request_count":0,"message_send_attempt_count":0,"sensitive_output_count":0}'
)
`;
}

export async function renderAruReadOnlyPreflightDownloadStage(checkoutRoot = sourceCheckoutRoot()) {
  const entries = [];
  for (const spec of SOURCE_SPECS) entries.push(await readExactSource(checkoutRoot, spec));
  const script = renderDownloadStage(entries);
  return Object.freeze({
    script,
    sha256: sha256(Buffer.from(script, "utf8")),
    size: Buffer.byteLength(script, "utf8"),
    releaseDigest: sha256(serializeReleaseManifest(entries)),
    entries: Object.freeze(entries.map(({ bytes, ...entry }) => Object.freeze(entry))),
  });
}

function directInvocation() {
  try {
    return process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
  } catch {
    return false;
  }
}

if (directInvocation()) {
  if (process.argv.length !== 2) {
    process.stderr.write(`{"ok":false,"operation":"${OPERATION}","error_code":"ARU_DISCORD_PREFLIGHT_DOWNLOAD_STAGE_SOURCE_REJECTED","sensitive_output_count":0}\\n`);
    process.exitCode = 2;
  } else {
    try {
      process.stdout.write((await renderAruReadOnlyPreflightDownloadStage()).script);
    } catch {
      process.stderr.write(`{"ok":false,"operation":"${OPERATION}","error_code":"ARU_DISCORD_PREFLIGHT_DOWNLOAD_STAGE_SOURCE_REJECTED","sensitive_output_count":0}\\n`);
      process.exitCode = 2;
    }
  }
}

export { SOURCE_SPECS };
