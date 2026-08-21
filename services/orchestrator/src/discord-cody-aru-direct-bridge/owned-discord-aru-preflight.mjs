import { isProxy } from "node:util/types";
import { createHash } from "node:crypto";

export const DISCORD_CODY_ARU_DIRECT_BRIDGE_ARU_READ_ONLY_PREFLIGHT_SCHEMA =
  "hermes-agents-discord-cody-aru-direct-bridge-aru-read-only-preflight/v1";

const DISCORD_API_ROOT = "https://discord.com/api/v10";
const REQUEST_TIMEOUT_MS = 10_000;
const SNOWFLAKE = /^[1-9][0-9]{15,19}$/u;
const TOKEN = /^[A-Za-z0-9._-]{20,4096}$/u;
const ACTION_REFERENCE = /^[A-Za-z0-9._-]{8,160}$/u;
const errorCodes = new WeakMap();

function error(code) {
  const value = new Error(code);
  value.name = "DiscordCodyAruDirectBridgeAruReadOnlyPreflightError";
  value.code = code;
  errorCodes.set(value, code);
  Object.defineProperty(value, "stack", {
    configurable: false,
    enumerable: false,
    writable: false,
    value: `${value.name}: ${code}`,
  });
  return value;
}

function fail(code) { throw error(code); }

function plainObject(value) {
  try {
    return value !== null
      && typeof value === "object"
      && !Array.isArray(value)
      && !isProxy(value)
      && (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
  } catch {
    return false;
  }
}

function exactOwnData(value, keys) {
  try {
    if (!plainObject(value) || Reflect.ownKeys(value).length !== keys.length) return null;
    const output = {};
    for (const key of keys) {
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (!descriptor || !("value" in descriptor) || !descriptor.enumerable) return null;
      output[key] = descriptor.value;
    }
    return output;
  } catch {
    return null;
  }
}

function ownData(value, key) {
  try {
    if (!plainObject(value)) return { invalid: true };
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor || !("value" in descriptor) || !descriptor.enumerable) return { invalid: true };
    return { value: descriptor.value };
  } catch {
    return { invalid: true };
  }
}

function isSnowflake(value) {
  return typeof value === "string" && SNOWFLAKE.test(value);
}

function isActionReference(value) {
  return typeof value === "string" && ACTION_REFERENCE.test(value);
}

function bindings(value) {
  const candidate = exactOwnData(value, ["discord_channel_id", "cody_bot_user_id", "aru_bot_user_id"]);
  if (
    candidate === null
    || !isSnowflake(candidate.discord_channel_id)
    || !isSnowflake(candidate.cody_bot_user_id)
    || !isSnowflake(candidate.aru_bot_user_id)
    || new Set([
      candidate.discord_channel_id,
      candidate.cody_bot_user_id,
      candidate.aru_bot_user_id,
    ]).size !== 3
  ) fail("DISCORD_CODY_ARU_DIRECT_BRIDGE_ARU_PREFLIGHT_PRECONDITION_REJECTED");
  return Object.freeze({ ...candidate });
}

function dependencies(value) {
  const candidate = exactOwnData(value, [
    "fixed_bindings",
    "action_reference",
    "claim_action",
    "read_private_token",
    "fetch",
  ]);
  if (
    candidate === null
    || !isActionReference(candidate.action_reference)
    || typeof candidate.claim_action !== "function"
    || isProxy(candidate.claim_action)
    || typeof candidate.read_private_token !== "function"
    || isProxy(candidate.read_private_token)
    || typeof candidate.fetch !== "function"
    || isProxy(candidate.fetch)
  ) fail("DISCORD_CODY_ARU_DIRECT_BRIDGE_ARU_PREFLIGHT_PRECONDITION_REJECTED");
  return Object.freeze({
    fixedBindings: bindings(candidate.fixed_bindings),
    actionReference: candidate.action_reference,
    claimAction: candidate.claim_action,
    readPrivateToken: candidate.read_private_token,
    fetch: candidate.fetch,
  });
}

function result(terminalState, terminalReason, identityGets, channelGets) {
  return Object.freeze({
    schema_version: DISCORD_CODY_ARU_DIRECT_BRIDGE_ARU_READ_ONLY_PREFLIGHT_SCHEMA,
    operation: "aru_discord_read_only_preflight",
    terminal_state: terminalState,
    terminal_reason: terminalReason,
    identity_get_attempt_count: identityGets,
    channel_get_attempt_count: channelGets,
    message_send_attempt_count: 0,
    message_history_read_count: 0,
    message_content_read_count: 0,
    retry_permitted: false,
    retry_count: 0,
    model_call_count: 0,
    sensitive_output_count: 0,
  });
}

async function json200(response, signal) {
  try {
    if (
      response === null
      || typeof response !== "object"
      || isProxy(response)
      || response.status !== 200
      || typeof response.json !== "function"
    ) return null;
    if (signal?.aborted) return null;
    const bodyRead = response.json();
    return await Promise.race([
      bodyRead,
      new Promise((resolve) => {
        if (!signal || typeof signal.addEventListener !== "function") return;
        signal.addEventListener("abort", () => resolve(null), { once: true });
      }),
    ]);
  } catch {
    return null;
  }
}

async function requestJson200(fetchImplementation, url, token) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetchImplementation(url, Object.freeze({
      method: "GET",
      headers: Object.freeze({
        Authorization: `Bot ${token}`,
        Accept: "application/json",
      }),
      redirect: "error",
      signal: controller.signal,
    }));
    return await json200(response, controller.signal);
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function actionReferenceDigest(actionReference) {
  return createHash("sha256").update(actionReference, "utf8").digest("hex");
}

function aruIdentity(body) {
  const id = ownData(body, "id");
  const bot = ownData(body, "bot");
  if (id.invalid || bot.invalid || !isSnowflake(id.value) || bot.value !== true) return null;
  return id.value;
}

function guildTextChannel(body) {
  const id = ownData(body, "id");
  const type = ownData(body, "type");
  const guildId = ownData(body, "guild_id");
  if (
    id.invalid || type.invalid || guildId.invalid
    || !isSnowflake(id.value)
    || type.value !== 0
    || !isSnowflake(guildId.value)
  ) return null;
  return id.value;
}

async function runOneShot(dependenciesValue) {
  let claimed;
  try {
    claimed = await dependenciesValue.claimAction(actionReferenceDigest(dependenciesValue.actionReference));
  } catch {
    fail("DISCORD_CODY_ARU_DIRECT_BRIDGE_ARU_PREFLIGHT_PRECONDITION_REJECTED");
  }
  if (claimed !== "new" && claimed !== "already_consumed") {
    fail("DISCORD_CODY_ARU_DIRECT_BRIDGE_ARU_PREFLIGHT_PRECONDITION_REJECTED");
  }
  if (claimed === "already_consumed") {
    return result("rejected", "action_reference_already_consumed", 0, 0);
  }
  let token;
  try {
    token = await dependenciesValue.readPrivateToken();
  } catch {
    fail("DISCORD_CODY_ARU_DIRECT_BRIDGE_ARU_PREFLIGHT_PRECONDITION_REJECTED");
  }
  if (typeof token !== "string" || !TOKEN.test(token)) {
    fail("DISCORD_CODY_ARU_DIRECT_BRIDGE_ARU_PREFLIGHT_PRECONDITION_REJECTED");
  }
  try {
    const identity = aruIdentity(await requestJson200(
      dependenciesValue.fetch,
      `${DISCORD_API_ROOT}/users/@me`,
      token,
    ));
    if (identity === null) return result("unavailable", "aru_identity_unavailable", 1, 0);
    if (identity !== dependenciesValue.fixedBindings.aru_bot_user_id) {
      return result("rejected", "aru_identity_rejected", 1, 0);
    }

    const channel = guildTextChannel(await requestJson200(
      dependenciesValue.fetch,
      `${DISCORD_API_ROOT}/channels/${dependenciesValue.fixedBindings.discord_channel_id}`,
      token,
    ));
    if (channel === null) return result("unavailable", "channel_binding_unavailable", 1, 1);
    if (channel !== dependenciesValue.fixedBindings.discord_channel_id) {
      return result("rejected", "channel_binding_rejected", 1, 1);
    }
    return result("verified", "channel_binding_verified", 1, 1);
  } finally {
    // The only credential reference is this invocation-local variable. It is
    // never placed in a result, error, manifest, environment variable, or file.
    token = undefined;
  }
}

// The caller provides the fixed non-secret binding and a hidden-input reader.
// This module has no production configuration, persistence, listener, retry,
// model, message, or import-time network surface.
export function createDiscordCodyAruDirectBridgeAruReadOnlyPreflight(options) {
  if (arguments.length !== 1) {
    fail("DISCORD_CODY_ARU_DIRECT_BRIDGE_ARU_PREFLIGHT_PRECONDITION_REJECTED");
  }
  const normalized = dependencies(options);
  let consumed = false;
  return Object.freeze({
    async preflight() {
      if (arguments.length !== 0 || consumed) {
        fail("DISCORD_CODY_ARU_DIRECT_BRIDGE_ARU_PREFLIGHT_ALREADY_CONSUMED_OR_AMBIGUOUS");
      }
      consumed = true;
      return runOneShot(normalized);
    },
  });
}

// Test-only alias makes synthetic fake-fetch coverage explicit. It does not
// access process configuration or contact Discord on construction.
export function createDiscordCodyAruDirectBridgeAruReadOnlyPreflightForTest(options) {
  return createDiscordCodyAruDirectBridgeAruReadOnlyPreflight(options);
}

export function discordCodyAruDirectBridgeAruPreflightErrorCode(value) {
  return errorCodes.get(value);
}
