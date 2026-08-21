// Separately launched Unix-only, one-shot Aru preflight. All operator values,
// including the credential, are accepted only from the controlling TTY with
// echo disabled. It accepts no environment input. Its only runtime state is a
// fixed, pre-created, owner-only root used for a durable opaque action latch.

import { resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";

const OPERATION = "aru_discord_read_only_preflight";
const FIXED_RUNTIME_ROOT = "/root/.hermes-cody-aru-preflight/runtime";
const FIXED_RUNTIME_ANCESTOR_PATHS = Object.freeze([
  "/",
  "/root",
  "/root/.hermes-cody-aru-preflight",
  FIXED_RUNTIME_ROOT,
]);
const LATCH_DIRECTORY_BASENAME = "aru-preflight-latches";
const POSIX_OWNER_PERMISSION_MASK = 0o700n;
const POSIX_GROUP_OR_OTHER_PERMISSION_MASK = 0o077n;
const POSIX_GROUP_OR_OTHER_WRITE_PERMISSION_MASK = 0o022n;
const POSIX_SPECIAL_PERMISSION_MASK = 0o7000n;
const ACTION_DIGEST = /^[a-f0-9]{64}$/u;

function rejectRuntime() { throw new Error("protected runtime rejected"); }

function fixedRuntimeRoot(pathModule) {
  if (!pathModule.isAbsolute(FIXED_RUNTIME_ROOT)) rejectRuntime();
  const root = pathModule.resolve(FIXED_RUNTIME_ROOT);
  if (root !== FIXED_RUNTIME_ROOT) rejectRuntime();
  return root;
}

function sameIdentity(left, right) {
  return left.dev === right.dev && left.ino === right.ino;
}

function protectedDirectory(stat, getuid, expectedIdentity = null) {
  const uid = getuid();
  if (
    !Number.isSafeInteger(uid)
    || uid < 0
    || !stat.isDirectory()
    || stat.isSymbolicLink()
    || stat.uid !== BigInt(uid)
    || (stat.mode & POSIX_GROUP_OR_OTHER_PERMISSION_MASK) !== 0n
    || (expectedIdentity !== null && !sameIdentity(expectedIdentity, stat))
  ) rejectRuntime();
  return Object.freeze({ dev: stat.dev, ino: stat.ino });
}

function protectedAnchorDirectory(stat, getuid, expectedIdentity = null) {
  const uid = getuid();
  if (
    !Number.isSafeInteger(uid)
    || uid < 0
    || !stat.isDirectory()
    || stat.isSymbolicLink()
    || stat.uid !== BigInt(uid)
    || (stat.mode & POSIX_OWNER_PERMISSION_MASK) !== POSIX_OWNER_PERMISSION_MASK
    || (stat.mode & POSIX_GROUP_OR_OTHER_WRITE_PERMISSION_MASK) !== 0n
    || (stat.mode & POSIX_SPECIAL_PERMISSION_MASK) !== 0n
    || (expectedIdentity !== null && !sameIdentity(expectedIdentity, stat))
  ) rejectRuntime();
  return Object.freeze({ dev: stat.dev, ino: stat.ino });
}

function fixedAnchorPath(path) {
  return path === "/" || path === "/root";
}

function protectedLatchFile(stat, getuid, expectedIdentity = null, { consumed = true } = {}) {
  const uid = getuid();
  if (
    !Number.isSafeInteger(uid)
    || uid < 0
    || !stat.isFile()
    || stat.isSymbolicLink()
    || stat.nlink !== 1n
    || (consumed && stat.size !== 9n)
    || (!consumed && stat.size !== 0n)
    || stat.uid !== BigInt(uid)
    || (stat.mode & POSIX_GROUP_OR_OTHER_PERMISSION_MASK) !== 0n
    || (expectedIdentity !== null && !sameIdentity(expectedIdentity, stat))
  ) rejectRuntime();
  return Object.freeze({ dev: stat.dev, ino: stat.ino });
}

function fixedChildPath(root, basename, pathModule) {
  const candidate = pathModule.join(root, basename);
  const prefix = root.endsWith(pathModule.sep) ? root : `${root}${pathModule.sep}`;
  if (!candidate.startsWith(prefix)) rejectRuntime();
  return candidate;
}

function createDirectorySynchronizer({ fsPromises, fsConstants, getuid }) {
  const flags = fsConstants.O_RDONLY | fsConstants.O_DIRECTORY;
  return async (directory, expectedIdentity) => {
    let handle;
    try {
      handle = await fsPromises.open(directory, flags);
      protectedDirectory(await handle.stat({ bigint: true }), getuid, expectedIdentity);
      await handle.sync();
      protectedDirectory(await handle.stat({ bigint: true }), getuid, expectedIdentity);
    } finally {
      if (handle !== undefined) await handle.close();
    }
  };
}

function normalizeAncestorPaths(root, ancestorPaths, pathModule) {
  if (
    !Array.isArray(ancestorPaths)
    || ancestorPaths.length < 2
    || ancestorPaths.at(-1) !== root
  ) rejectRuntime();
  for (let index = 0; index < ancestorPaths.length; index += 1) {
    const candidate = ancestorPaths[index];
    if (typeof candidate !== "string" || !pathModule.isAbsolute(candidate) || pathModule.resolve(candidate) !== candidate) {
      rejectRuntime();
    }
    if (index === 0) {
      if (candidate !== pathModule.parse(candidate).root) rejectRuntime();
    } else if (pathModule.dirname(candidate) !== ancestorPaths[index - 1]) {
      rejectRuntime();
    }
  }
  return Object.freeze([...ancestorPaths]);
}

async function captureProtectedAncestorChain({ ancestorPaths, fsPromises, getuid, expectedIdentities = null }) {
  const identities = [];
  for (let index = 0; index < ancestorPaths.length; index += 1) {
    const stat = await fsPromises.lstat(ancestorPaths[index], { bigint: true });
    const expectedIdentity = expectedIdentities?.[index] ?? null;
    identities.push(fixedAnchorPath(ancestorPaths[index])
      ? protectedAnchorDirectory(stat, getuid, expectedIdentity)
      : protectedDirectory(stat, getuid, expectedIdentity));
  }
  return Object.freeze(identities);
}

async function prepareProtectedLatchRoot({ root, ancestorPaths, fsPromises, pathModule, getuid, syncDirectory }) {
  const normalizedAncestors = normalizeAncestorPaths(root, ancestorPaths, pathModule);
  const initialAncestors = await captureProtectedAncestorChain({
    ancestorPaths: normalizedAncestors,
    fsPromises,
    getuid,
  });
  const initialRoot = initialAncestors.at(-1);
  const latchDirectory = fixedChildPath(root, LATCH_DIRECTORY_BASENAME, pathModule);
  let latchDirectoryCreated = false;
  try {
    await fsPromises.mkdir(latchDirectory, { mode: 0o700 });
    latchDirectoryCreated = true;
  } catch (caught) {
    if (caught?.code !== "EEXIST") throw caught;
  }
  await captureProtectedAncestorChain({
    ancestorPaths: normalizedAncestors,
    fsPromises,
    getuid,
    expectedIdentities: initialAncestors,
  });
  const latchIdentity = protectedDirectory(await fsPromises.lstat(latchDirectory, { bigint: true }), getuid);
  if (latchDirectoryCreated) await syncDirectory(root, initialRoot);
  await captureProtectedAncestorChain({
    ancestorPaths: normalizedAncestors,
    fsPromises,
    getuid,
    expectedIdentities: initialAncestors,
  });
  return Object.freeze({
    root,
    rootIdentity: initialRoot,
    ancestorPaths: normalizedAncestors,
    ancestorIdentities: initialAncestors,
    directory: latchDirectory,
    directoryIdentity: latchIdentity,
    getuid,
    syncDirectory,
  });
}

function createClaimAction({ protectedLatch, fsPromises, fsConstants, pathModule }) {
  const flags = fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_NOFOLLOW;
  return async (actionReferenceDigest) => {
    if (typeof actionReferenceDigest !== "string" || !ACTION_DIGEST.test(actionReferenceDigest)) rejectRuntime();
    await captureProtectedAncestorChain({
      ancestorPaths: protectedLatch.ancestorPaths,
      fsPromises,
      getuid: protectedLatch.getuid,
      expectedIdentities: protectedLatch.ancestorIdentities,
    });
    protectedDirectory(
      await fsPromises.lstat(protectedLatch.directory, { bigint: true }),
      protectedLatch.getuid,
      protectedLatch.directoryIdentity,
    );
    const latchPath = fixedChildPath(
      protectedLatch.directory,
      `aru-preflight-${actionReferenceDigest}.latch`,
      pathModule,
    );
    let handle;
    try {
      handle = await fsPromises.open(latchPath, flags, 0o600);
    } catch (caught) {
      if (caught?.code !== "EEXIST") throw caught;
      await captureProtectedAncestorChain({
        ancestorPaths: protectedLatch.ancestorPaths,
        fsPromises,
        getuid: protectedLatch.getuid,
        expectedIdentities: protectedLatch.ancestorIdentities,
      });
      protectedDirectory(
        await fsPromises.lstat(protectedLatch.directory, { bigint: true }),
        protectedLatch.getuid,
        protectedLatch.directoryIdentity,
      );
      protectedLatchFile(await fsPromises.lstat(latchPath, { bigint: true }), protectedLatch.getuid);
      return "already_consumed";
    }
    try {
      await captureProtectedAncestorChain({
        ancestorPaths: protectedLatch.ancestorPaths,
        fsPromises,
        getuid: protectedLatch.getuid,
        expectedIdentities: protectedLatch.ancestorIdentities,
      });
      protectedDirectory(
        await fsPromises.lstat(protectedLatch.directory, { bigint: true }),
        protectedLatch.getuid,
        protectedLatch.directoryIdentity,
      );
      const initialFile = protectedLatchFile(
        await handle.stat({ bigint: true }),
        protectedLatch.getuid,
        null,
        { consumed: false },
      );
      await handle.writeFile("consumed\n", "utf8");
      await handle.sync();
      protectedLatchFile(await handle.stat({ bigint: true }), protectedLatch.getuid, initialFile);
      protectedLatchFile(await fsPromises.lstat(latchPath, { bigint: true }), protectedLatch.getuid, initialFile);
      await protectedLatch.syncDirectory(protectedLatch.directory, protectedLatch.directoryIdentity);
      protectedDirectory(
        await fsPromises.lstat(protectedLatch.directory, { bigint: true }),
        protectedLatch.getuid,
        protectedLatch.directoryIdentity,
      );
      await captureProtectedAncestorChain({
        ancestorPaths: protectedLatch.ancestorPaths,
        fsPromises,
        getuid: protectedLatch.getuid,
        expectedIdentities: protectedLatch.ancestorIdentities,
      });
      return "new";
    } finally {
      await handle.close();
    }
  };
}

function readNoEchoPrivateLine(label) {
  return new Promise((resolve, reject) => {
    const input = process.stdin;
    const output = process.stderr;
    if (
      !input.isTTY
      || !output.isTTY
      || typeof input.setRawMode !== "function"
      || typeof label !== "string"
    ) {
      reject(new Error("private terminal input unavailable"));
      return;
    }
    let value = "";
    let finished = false;
    const wasRaw = input.isRaw === true;
    const finish = (caught, resultValue = undefined) => {
      if (finished) return;
      finished = true;
      input.off("data", onData);
      input.off("end", onEnd);
      input.off("error", onError);
      try {
        input.setRawMode(wasRaw);
      } catch {
        // A restoration failure is reported only as a sanitized rejected run.
      }
      output.write("\n");
      if (caught) reject(caught);
      else resolve(resultValue);
    };
    const onEnd = () => finish(new Error("private input ended"));
    const onError = () => finish(new Error("private input failed"));
    const onData = (chunk) => {
      const text = Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
      for (const character of text) {
        if (character === "\r" || character === "\n") {
          finish(null, value);
          return;
        }
        if (character === "\u0003" || character === "\u0004") {
          finish(new Error("private input canceled"));
          return;
        }
        if (character === "\b" || character === "\u007f") {
          value = value.slice(0, -1);
          continue;
        }
        if (character.codePointAt(0) < 0x20) {
          finish(new Error("private input rejected"));
          return;
        }
        value += character;
        if (Buffer.byteLength(value, "utf8") > 4096) {
          finish(new Error("private input rejected"));
          return;
        }
      }
    };
    try {
      output.write(`Enter private ${label}: `);
      input.setRawMode(true);
      input.resume();
      input.on("data", onData);
      input.once("end", onEnd);
      input.once("error", onError);
    } catch (caught) {
      finish(caught);
    }
  });
}

function safeOutput(result) {
  return {
    ok: result.terminal_state === "verified",
    operation: result.operation,
    terminal_state: result.terminal_state,
    terminal_reason: result.terminal_reason,
    identity_get_attempt_count: result.identity_get_attempt_count,
    channel_get_attempt_count: result.channel_get_attempt_count,
    message_send_attempt_count: result.message_send_attempt_count,
    message_history_read_count: result.message_history_read_count,
    message_content_read_count: result.message_content_read_count,
    retry_permitted: result.retry_permitted,
    retry_count: result.retry_count,
    model_call_count: result.model_call_count,
    sensitive_output_count: result.sensitive_output_count,
  };
}

function sanitizedFailure() {
  return {
    ok: false,
    operation: OPERATION,
    error_code: "DISCORD_CODY_ARU_DIRECT_BRIDGE_ARU_PREFLIGHT_PRECONDITION_REJECTED",
    result_emitted: false,
    sensitive_output_count: 0,
  };
}

function isDirectInvocation() {
  try {
    return typeof process.argv[1] === "string"
      && resolvePath(process.argv[1]) === fileURLToPath(import.meta.url);
  } catch {
    return false;
  }
}

if (isDirectInvocation()) try {
  if (process.argv.length !== 2 || process.platform === "win32") {
    throw new Error("unsupported invocation");
  }
  const [
    fsPromises,
    { constants: fsConstants },
    pathModule,
  ] = await Promise.all([
    import("node:fs/promises"),
    import("node:fs"),
    import("node:path"),
  ]);
  if (
    typeof process.getuid !== "function"
    || process.getuid() !== 0
    || !Number.isInteger(fsConstants.O_WRONLY)
    || !Number.isInteger(fsConstants.O_CREAT)
    || !Number.isInteger(fsConstants.O_EXCL)
    || !Number.isInteger(fsConstants.O_NOFOLLOW)
    || !Number.isInteger(fsConstants.O_RDONLY)
    || !Number.isInteger(fsConstants.O_DIRECTORY)
  ) throw new Error("protected runtime unavailable");
  const {
    createDiscordCodyAruDirectBridgeAruReadOnlyPreflight,
  } = await import("./discord-cody-aru-direct-bridge/owned-discord-aru-preflight.mjs");
  const protectedLatch = await prepareProtectedLatchRoot({
    root: fixedRuntimeRoot(pathModule),
    ancestorPaths: FIXED_RUNTIME_ANCESTOR_PATHS,
    fsPromises,
    pathModule,
    getuid: process.getuid,
    syncDirectory: createDirectorySynchronizer({
      fsPromises,
      fsConstants,
      getuid: process.getuid,
    }),
  });
  const fixedBindings = {
    discord_channel_id: await readNoEchoPrivateLine("Discord channel ID"),
    cody_bot_user_id: await readNoEchoPrivateLine("expected Cody bot user ID"),
    aru_bot_user_id: await readNoEchoPrivateLine("expected Aru bot user ID"),
  };
  const preflight = createDiscordCodyAruDirectBridgeAruReadOnlyPreflight({
    fixed_bindings: fixedBindings,
    action_reference: await readNoEchoPrivateLine("one-time approval reference"),
    claim_action: createClaimAction({
      protectedLatch,
      fsPromises,
      fsConstants,
      pathModule,
    }),
    read_private_token: () => readNoEchoPrivateLine("Aru bot token"),
    fetch: globalThis.fetch,
  });
  const output = safeOutput(await preflight.preflight());
  process.stdout.write(`${JSON.stringify(output)}\n`);
  if (!output.ok) process.exitCode = 2;
} catch {
  process.stdout.write(`${JSON.stringify(sanitizedFailure())}\n`);
  process.exitCode = 2;
}

export {
  createClaimAction,
  createDirectorySynchronizer,
  prepareProtectedLatchRoot,
};
