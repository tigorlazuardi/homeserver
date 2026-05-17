import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { existsSync } from "node:fs";
import {
  chmod,
  mkdir,
  readFile,
  rename,
  writeFile,
  appendFile,
  unlink,
  stat,
} from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

// ─── Image Resize ──────────────────────────────────────────────────

async function isFfmpegAvailable(): Promise<boolean> {
  try {
    await execFileAsync("ffmpeg", ["-version"], { timeout: 5000 });
    return true;
  } catch {
    return false;
  }
}

async function resizeImageWithFfmpeg(inputPath: string, outputPath: string, quality = 2): Promise<boolean> {
  try {
    await execFileAsync("ffmpeg", [
      "-i", inputPath,
      "-vf", "scale=2000:2000:force_original_aspect_ratio=decrease",
      "-q:v", String(quality),
      "-y",
      outputPath,
    ], { timeout: 30000 });
    return true;
  } catch {
    return false;
  }
}

async function processImageFile(inputPath: string): Promise<string | undefined> {
  // Check original size first
  let originalSize = Infinity;
  try {
    originalSize = (await stat(inputPath)).size;
  } catch {
    return undefined;
  }

  const ffmpegOk = await isFfmpegAvailable();
  if (!ffmpegOk) {
    if (originalSize <= MAX_IMAGE_FILE_BYTES) return inputPath;
    logError("Image too large and ffmpeg unavailable:", inputPath, `${(originalSize / 1024 / 1024).toFixed(1)}MB`);
    return undefined;
  }

  let currentPath = inputPath;
  let lastGoodPath: string | undefined;

  for (const quality of [2, 4, 6, 8]) {
    const outPath = `${inputPath}.resized.q${quality}.jpg`;
    const ok = await resizeImageWithFfmpeg(currentPath, outPath, quality);
    if (!ok) continue;

    let size = Infinity;
    try {
      size = (await stat(outPath)).size;
    } catch {
      continue;
    }
    logInfo(`processImageFile: quality=${quality} size=${size} bytes (${(size / 1024 / 1024).toFixed(1)}MB)`);

    if (size <= MAX_IMAGE_FILE_BYTES) {
      lastGoodPath = outPath;
      break;
    }
    currentPath = outPath;
  }

  if (lastGoodPath) {
    // Clean up original and any failed intermediates
    try { await unlink(inputPath); } catch {}
    for (const quality of [2, 4, 6, 8]) {
      const p = `${inputPath}.resized.q${quality}.jpg`;
      if (p !== lastGoodPath) {
        try { await unlink(p); } catch {}
      }
    }
    return lastGoodPath;
  }

  logError("Failed to compress image under limit:", inputPath);
  for (const quality of [2, 4, 6, 8]) {
    try { await unlink(`${inputPath}.resized.q${quality}.jpg`); } catch {}
  }
  return undefined;
}

// ─── File Logger ─────────────────────────────────────────────────────

const LOG_BASE_DIR = join(homedir(), ".pi", "agent", "logs", "pi-telegram-multi");

let currentLogFile = join(LOG_BASE_DIR, "default", "pi-telegram-multi.log");

function setLogSession(sessionId: string): void {
  currentLogFile = join(LOG_BASE_DIR, sessionId, "pi-telegram-multi.log");
  mkdir(dirname(currentLogFile), { recursive: true }).catch(() => {});
}

async function fileLog(level: string, ...args: unknown[]): Promise<void> {
  const timestamp = new Date().toISOString();
  const message = args.map((a) =>
    typeof a === "string" ? a : JSON.stringify(a)
  ).join(" ");
  const line = `[${timestamp}] [${level}] ${message}\n`;
  try {
    await mkdir(dirname(currentLogFile), { recursive: true });
    await appendFile(currentLogFile, line, "utf8");
  } catch {
    // silently ignore log write failures
  }
}

function logInfo(...args: unknown[]): void {
  fileLog("INFO", ...args).catch(() => {});
}

function logError(...args: unknown[]): void {
  fileLog("ERROR", ...args).catch(() => {});
}

// ─── Types ───────────────────────────────────────────────────────────

interface TelegramMessage {
  message_id: number;
  from?: { id: number; username?: string; first_name?: string };
  chat: { id: number; type: string };
  date: number;
  text?: string;
  caption?: string;
  reply_to_message?: TelegramMessage;
  photo?: Array<{ file_id: string; file_unique_id: string; file_size?: number; width: number; height: number }>;
  video?: { file_id: string; file_unique_id: string; file_size?: number; width?: number; height?: number; duration?: number; mime_type?: string };
  document?: { file_id: string; file_unique_id: string; file_name?: string; file_size?: number; mime_type?: string };
  voice?: { file_id: string; file_unique_id: string; file_size?: number; duration?: number; mime_type?: string };
  audio?: { file_id: string; file_unique_id: string; file_name?: string; file_size?: number; duration?: number; mime_type?: string };
  animation?: { file_id: string; file_unique_id: string; file_size?: number; width?: number; height?: number; duration?: number };
  media_group_id?: string;
}

interface TelegramUpdate {
  update_id: number;
  message?: TelegramMessage;
  edited_message?: TelegramMessage;
  callback_query?: {
    id: string;
    from: { id: number };
    message?: { message_id: number; chat: { id: number }; text?: string };
    data?: string;
  };
  message_reaction?: {
    chat: { id: number };
    message_id: number;
    user?: { id: number };
    new_reaction?: Array<{ type: string; emoji?: string }>;
  };
}

interface TelegramConfig {
  botToken: string;
  chatId?: number;
  allowedUserId?: number;
  botUsername?: string;
  botId?: number;
  lastUpdateId?: number;
  proactivePush?: boolean;
}

interface LockEntry {
  pid: number;
  ts: number;
  chatId?: number;
  allowedUserId?: number;
}

interface LocksFile {
  [botTokenHash: string]: LockEntry;
}

interface QueuedItem {
  id: string;
  text: string;
  images?: Array<{ type: "image"; source: { type: "path"; path: string } }>;
  files?: string[];
  priority: number;
  sourceMessageId?: number;
  chatId: number;
  timestamp: number;
}

interface ActiveTurn {
  chatId: number;
  sourceMessageId: number;
}

function stripTrailingEllipsis(text: string): string {
  let cleaned = text.trimEnd();
  cleaned = cleaned.replace(/(…+|\.{3,})\s*$/g, "").trimEnd();
  cleaned = cleaned.replace(/(…+|\.{3,})\s*$/g, "").trimEnd();
  return cleaned || text;
}

function guessImageMimeType(filePath: string): string | undefined {
  const normalized = filePath.toLowerCase();
  if (normalized.endsWith(".jpg") || normalized.endsWith(".jpeg")) return "image/jpeg";
  if (normalized.endsWith(".png")) return "image/png";
  if (normalized.endsWith(".webp")) return "image/webp";
  if (normalized.endsWith(".gif")) return "image/gif";
  return undefined;
}

const MAX_IMAGE_FILE_BYTES = 4.5 * 1024 * 1024;

async function imagePathToBase64Content(path: string): Promise<{ type: "image"; source: { type: "base64"; media_type: string; data: string } } | undefined> {
  try {
    const fileStat = await stat(path);
    logInfo(`imagePathToBase64Content: path=${path} size=${fileStat.size} bytes`);
    if (fileStat.size > MAX_IMAGE_FILE_BYTES) {
      logError("Image file too large after resize, skipping:", path, `${(fileStat.size / 1024 / 1024).toFixed(1)}MB`);
      return undefined;
    }
    const buffer = await readFile(path);
    const mimeType = guessImageMimeType(path) ?? "image/jpeg";
    const base64 = Buffer.from(buffer).toString("base64");
    logInfo(`imagePathToBase64Content: base64Len=${base64.length} mimeType=${mimeType}`);
    return { type: "image", source: { type: "base64", media_type: mimeType, data: base64 } };
  } catch (err) {
    logError("Failed to read image file:", path, err);
    return undefined;
  }
}

// ─── Env / Config ────────────────────────────────────────────────────

function getAgentDir(): string {
  return process.env.PI_CODING_AGENT_DIR
    ? resolve(process.env.PI_CODING_AGENT_DIR)
    : join(homedir(), ".pi", "agent");
}

function getLocksPath(): string {
  return join(getAgentDir(), "telegram-locks.json");
}

function getBotIdFromToken(token: string): string {
  // Bot token format: <numeric_bot_id>:<random_string>
  // Use the numeric bot ID directly — readable and unique per bot
  const botId = token.split(":")[0];
  if (/^\d+$/.test(botId)) return botId;
  // Fallback for malformed tokens
  return createHash("sha256").update(token).digest("hex").slice(0, 16);
}

function loadEnvConfig(): TelegramConfig | undefined {
  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_CHAT_ID
    ? Number(process.env.TELEGRAM_CHAT_ID)
    : undefined;
  if (!botToken) return undefined;
  return { botToken, chatId };
}

const STALE_LOCK_MS = 60_000;
const HEARTBEAT_INTERVAL_MS = 30_000;

// ─── Locks ───────────────────────────────────────────────────────────

async function readLocks(): Promise<LocksFile> {
  const path = getLocksPath();
  if (!existsSync(path)) return {};
  try {
    const data = await readFile(path, "utf8");
    return JSON.parse(data) as LocksFile;
  } catch {
    return {};
  }
}

async function writeLocks(locks: LocksFile): Promise<void> {
  const dir = getAgentDir();
  const path = getLocksPath();
  await mkdir(dir, { recursive: true });
  const tmp = `${path}.tmp-${process.pid}-${Date.now()}`;
  const data = JSON.stringify(locks, null, "\t") + "\n";
  await writeFile(tmp, data, { encoding: "utf8", mode: 0o600 });
  await chmod(tmp, 0o600);
  await rename(tmp, path);
  await chmod(path, 0o600);
}

function isStale(entry: LockEntry): boolean {
  return Date.now() - entry.ts > STALE_LOCK_MS;
}

async function acquireLock(
  botToken: string,
  chatId?: number,
  allowedUserId?: number,
): Promise<{ acquired: boolean; existing?: LockEntry }> {
  const hash = getBotIdFromToken(botToken);
  const locks = await readLocks();
  const existing = locks[hash];
  if (existing) {
    // Own PID → refresh and continue
    if (existing.pid === process.pid) {
      locks[hash] = { pid: process.pid, ts: Date.now(), chatId, allowedUserId };
      await writeLocks(locks);
      return { acquired: true };
    }

    // Timestamp-based staleness check (handles crashed processes)
    if (isStale(existing)) {
      locks[hash] = { pid: process.pid, ts: Date.now(), chatId, allowedUserId };
      await writeLocks(locks);
      const verify = await readLocks();
      if (verify[hash]?.pid === process.pid) return { acquired: true };
      return { acquired: false, existing: verify[hash] };
    }

    // Cross-platform PID liveness check
    try {
      process.kill(existing.pid, 0);
      // PID still alive and not stale
      return { acquired: false, existing };
    } catch {
      // PID dead → take over
      locks[hash] = { pid: process.pid, ts: Date.now(), chatId, allowedUserId };
      await writeLocks(locks);
      const verify = await readLocks();
      if (verify[hash]?.pid === process.pid) return { acquired: true };
      return { acquired: false, existing: verify[hash] };
    }
  }
  locks[hash] = { pid: process.pid, ts: Date.now(), chatId, allowedUserId };
  await writeLocks(locks);
  const verify = await readLocks();
  if (verify[hash]?.pid === process.pid) return { acquired: true };
  return { acquired: false, existing: verify[hash] };
}

async function releaseLock(botToken: string): Promise<void> {
  const hash = getBotIdFromToken(botToken);
  const locks = await readLocks();
  if (locks[hash]?.pid === process.pid) {
    delete locks[hash];
    await writeLocks(locks);
  }
}

async function updateLock(
  botToken: string,
  patch: Partial<LockEntry>,
): Promise<void> {
  const hash = getBotIdFromToken(botToken);
  const locks = await readLocks();
  if (locks[hash]?.pid === process.pid) {
    locks[hash] = { ...locks[hash], ...patch };
    await writeLocks(locks);
  }
}

// ─── Telegram API ────────────────────────────────────────────────────

function tgApiUrl(botToken: string, method: string): string {
  return `https://api.telegram.org/bot${botToken}/${method}`;
}

async function tgFetch<T>(botToken: string, method: string, body?: unknown, signal?: AbortSignal): Promise<T | undefined> {
  try {
    const res = await fetch(tgApiUrl(botToken, method), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
      signal,
    });
    const json = (await res.json()) as { ok: boolean; result?: T; description?: string };
    if (!json.ok) {
      logError(`${method} failed (${res.status}):`, json.description, "| body:", JSON.stringify(body));
      return undefined;
    }
    return json.result;
  } catch (err) {
    logError(`${method} error:`, err);
    return undefined;
  }
}

async function deleteWebhook(botToken: string): Promise<void> {
  await tgFetch(botToken, "deleteWebhook", { drop_pending_updates: true });
}

async function getUpdates(
  botToken: string,
  opts: { offset?: number; limit?: number; timeout?: number; allowed_updates?: string[]; signal?: AbortSignal },
): Promise<TelegramUpdate[]> {
  try {
    const res = await fetch(tgApiUrl(botToken, "getUpdates"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(opts),
      signal: opts.signal,
    });
    const json = (await res.json()) as { ok: boolean; result?: TelegramUpdate[]; description?: string };
    if (!json.ok) {
      if (json.description?.includes("Conflict") || json.description?.includes("terminated by other")) {
        throw new Error(`409 Conflict: ${json.description}`);
      }
      logError(`getUpdates failed:`, json.description);
      return [];
    }
    return json.result ?? [];
  } catch (err) {
    if (err instanceof Error && err.message.includes("409 Conflict")) throw err;
    logError(`getUpdates error:`, err);
    return [];
  }
}

async function getFilePath(botToken: string, fileId: string): Promise<string | undefined> {
  const result = await tgFetch<{ file_path?: string }>(botToken, "getFile", { file_id: fileId });
  return result?.file_path;
}

async function sendMessage(
  botToken: string,
  chatId: number,
  text: string,
  opts?: { parse_mode?: string; reply_to_message_id?: number; disable_web_page_preview?: boolean },
): Promise<TelegramMessage | undefined> {
  if (!text || text.trim().length === 0) {
    logError("sendMessage skipped: empty text");
    return undefined;
  }
  return tgFetch<TelegramMessage>(botToken, "sendMessage", {
    chat_id: chatId,
    text,
    ...opts,
  });
}

async function sendMessageMultipart(
  botToken: string,
  chatId: number,
  text: string,
  filePath: string,
  fileField: string,
  opts?: { reply_to_message_id?: number },
): Promise<TelegramMessage | undefined> {
  try {
    const fileData = await readFile(filePath);
    const form = new FormData();
    form.append("chat_id", String(chatId));
    form.append(fileField, new Blob([fileData]), basename(filePath));
    if (text) form.append("caption", text);
    if (opts?.reply_to_message_id) form.append("reply_to_message_id", String(opts.reply_to_message_id));
    const res = await fetch(tgApiUrl(botToken, fileField === "video" ? "sendVideo" : fileField === "audio" ? "sendAudio" : fileField === "voice" ? "sendVoice" : fileField === "document" ? "sendDocument" : "sendPhoto"), {
      method: "POST",
      body: form,
    });
    const json = (await res.json()) as { ok: boolean; result?: TelegramMessage; description?: string };
    if (!json.ok) {
      logError("multipart send failed:", json.description);
      return undefined;
    }
    return json.result;
  } catch (err) {
    logError("multipart send error:", err);
    return undefined;
  }
}

async function editMessageText(
  botToken: string,
  chatId: number,
  messageId: number,
  text: string,
  opts?: { parse_mode?: string },
): Promise<boolean> {
  const result = await tgFetch<unknown>(botToken, "editMessageText", {
    chat_id: chatId,
    message_id: messageId,
    text,
    ...opts,
  });
  return !!result;
}

async function deleteMessage(botToken: string, chatId: number, messageId: number): Promise<boolean> {
  const result = await tgFetch<unknown>(botToken, "deleteMessage", {
    chat_id: chatId,
    message_id: messageId,
  });
  return !!result;
}

async function sendChatAction(botToken: string, chatId: number, action: string): Promise<void> {
  await tgFetch(botToken, "sendChatAction", { chat_id: chatId, action });
}

async function answerCallbackQuery(botToken: string, queryId: string, text?: string): Promise<void> {
  await tgFetch(botToken, "answerCallbackQuery", { callback_query_id: queryId, text });
}

async function setMyCommands(botToken: string, commands: Array<{ command: string; description: string }>): Promise<void> {
  await tgFetch(botToken, "setMyCommands", { commands });
}

async function setMessageReaction(botToken: string, chatId: number, messageId: number, emoji: string): Promise<void> {
  await tgFetch(botToken, "setMessageReaction", {
    chat_id: chatId,
    message_id: messageId,
    reaction: [{ type: "emoji", emoji }],
    is_big: false,
  });
}

async function getMe(botToken: string): Promise<{ id: number; username: string } | undefined> {
  return tgFetch(botToken, "getMe");
}

// ─── Temp Dir ────────────────────────────────────────────────────────

function getTempDir(botId: string, chatId: number, sessionId: string): string {
  return join(tmpdir(), "pi-telegram", botId, String(chatId), sessionId);
}

async function prepareTempDir(botId: string, chatId: number, sessionId: string): Promise<string> {
  const dir = getTempDir(botId, chatId, sessionId);
  await mkdir(dir, { recursive: true });
  return dir;
}

async function downloadTelegramFile(
  botToken: string,
  botId: string,
  chatId: number,
  sessionId: string,
  fileId: string,
  fileNameHint?: string,
): Promise<string | undefined> {
  const filePath = await getFilePath(botToken, fileId);
  if (!filePath) return undefined;
  const url = `https://api.telegram.org/file/bot${botToken}/${filePath}`;
  try {
    const res = await fetch(url);
    if (!res.ok) return undefined;
    const buffer = Buffer.from(await res.arrayBuffer());
    const dir = await prepareTempDir(botId, chatId, sessionId);
    const name = fileNameHint || basename(filePath) || `file-${Date.now()}`;
    const outPath = join(dir, name);
    await writeFile(outPath, buffer);
    return outPath;
  } catch (err) {
    logError("download error:", err);
    return undefined;
  }
}

// ─── Telegram HTML Rendering (adapted from llblab/pi-telegram) ───

const MAX_MESSAGE_LENGTH = 4096;

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function escapeHtmlAttribute(text: string): string {
  return escapeHtml(text).replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

interface OpenHtmlTag {
  name: string;
  openTag: string;
}

const TELEGRAM_VOID_HTML_TAGS = new Set(["br", "hr"]);

function getHtmlTagName(tag: string): string | undefined {
  return tag.match(/^<\/?\s*([a-zA-Z][\w-]*)/)?.[1]?.toLowerCase();
}

function isHtmlClosingTag(tag: string): boolean {
  return /^<\//.test(tag);
}

function isHtmlSelfClosingTag(tag: string): boolean {
  return /\/\s*>$/.test(tag);
}

function getHtmlClosingTags(openTags: OpenHtmlTag[]): string {
  return [...openTags]
    .reverse()
    .map((tag) => `</${tag.name}>`)
    .join("");
}

function getHtmlOpeningTags(openTags: OpenHtmlTag[]): string {
  return openTags.map((tag) => tag.openTag).join("");
}

function updateOpenHtmlTags(tag: string, openTags: OpenHtmlTag[]): void {
  const name = getHtmlTagName(tag);
  if (!name || TELEGRAM_VOID_HTML_TAGS.has(name)) return;
  if (isHtmlClosingTag(tag)) {
    const index = openTags.map((openTag) => openTag.name).lastIndexOf(name);
    if (index !== -1) openTags.splice(index, 1);
    return;
  }
  if (isHtmlSelfClosingTag(tag)) return;
  openTags.push({ name, openTag: tag });
}

function chunkHtmlPreservingTags(html: string, maxLength: number): string[] {
  if (html.length <= maxLength) return [html];
  const chunks: string[] = [];
  const openTags: OpenHtmlTag[] = [];
  const tagPattern = /<\/?[a-zA-Z][^>]*>/g;
  let current = "";
  let index = 0;
  const flushCurrent = (): void => {
    if (current.length === 0) return;
    chunks.push(`${current}${getHtmlClosingTags(openTags)}`);
    current = getHtmlOpeningTags(openTags);
  };
  const appendText = (text: string): void => {
    let remaining = text;
    while (remaining.length > 0) {
      const closingTags = getHtmlClosingTags(openTags);
      const available = maxLength - current.length - closingTags.length;
      if (available <= 0) {
        flushCurrent();
        continue;
      }
      const slice = remaining.slice(0, available);
      current += slice;
      remaining = remaining.slice(slice.length);
      if (remaining.length > 0) flushCurrent();
    }
  };
  const appendTag = (tag: string): void => {
    const closingTags = isHtmlClosingTag(tag)
      ? ""
      : getHtmlClosingTags(openTags);
    if (current.length + tag.length + closingTags.length > maxLength) {
      flushCurrent();
    }
    current += tag;
    updateOpenHtmlTags(tag, openTags);
  };
  for (const match of html.matchAll(tagPattern)) {
    appendText(html.slice(index, match.index));
    appendTag(match[0]);
    index = match.index + match[0].length;
  }
  appendText(html.slice(index));
  if (current.length > 0) chunks.push(current);
  return chunks;
}

// ─── Markdown → Telegram HTML ────────────────────────────────────────

function normalizeMarkdownDocument(markdown: string): string {
  const lines = markdown.replace(/\r\n/g, "\n").split("\n");
  let start = 0;
  while (start < lines.length && (lines[start] ?? "").trim().length === 0) {
    start += 1;
  }
  let end = lines.length;
  while (end > start && (lines[end - 1] ?? "").trim().length === 0) {
    end -= 1;
  }
  return lines.slice(start, end).join("\n");
}

function matchMarkdownHeadingLine(line: string): RegExpMatchArray | null {
  return line.match(/^(\s*)#{1,6}\s+(.+)$/);
}

function stripInlineMarkdownToPlainText(text: string): string {
  let result = text
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, "$1")
    .replace(/`([^`\n]+)`/g, "$1")
    .replace(/(\*\*\*|___)(.+?)\1/g, "$2")
    .replace(/(\*\*|__)(.+?)\1/g, "$2")
    .replace(/(\*|_)(.+?)\1/g, "$2")
    .replace(/~~(.+?)~~/g, "$1")
    .replace(/\\([\\`*_{}\[\]()#+\-.!>~|])/g, "$1");
  return result;
}

interface InlineMarkdownTokenState {
  tokens: string[];
}

function makeInlineMarkdownToken(state: InlineMarkdownTokenState, html: string): string {
  const token = `\uE000${state.tokens.length}\uE001`;
  state.tokens.push(html);
  return token;
}

function stashInlineMarkdownLinks(text: string, state: InlineMarkdownTokenState): string {
  return text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_match, label: string, destination: string) => {
    const plainLabel = stripInlineMarkdownToPlainText(label).trim();
    const renderedLabel = plainLabel.length > 0 ? plainLabel : destination;
    return makeInlineMarkdownToken(
      state,
      `<a href="${escapeHtmlAttribute(destination)}">${escapeHtml(renderedLabel)}</a>`,
    );
  });
}

function stashInlineMarkdownCodeSpans(text: string, state: InlineMarkdownTokenState): string {
  return text.replace(/`([^`\n]+)`/g, (_match, code: string) => {
    return makeInlineMarkdownToken(state, `<code>${escapeHtml(code)}</code>`);
  });
}

function renderDelimitedInlineStyle(text: string, delimiter: string, render: (content: string) => string): string {
  const escapedDelimiter = delimiter.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(
    `(^|[^\\p{L}\\p{N}\\\\])(${escapedDelimiter})(?=\\S)(.+?)(?<=\\S)\\2(?=[^\\p{L}\\p{N}]|$)`,
    "gu",
  );
  return text.replace(
    pattern,
    (_match, prefix: string, _wrapped: string, content: string) => {
      return `${prefix}${render(content)}`;
    },
  );
}

function applyInlineMarkdownStyles(text: string): string {
  let result = renderDelimitedInlineStyle(text, "***", (content) => `<b><i>${content}</i></b>`);
  result = renderDelimitedInlineStyle(result, "___", (content) => `<b><i>${content}</i></b>`);
  result = renderDelimitedInlineStyle(result, "~~", (content) => `<s>${content}</s>`);
  result = renderDelimitedInlineStyle(result, "**", (content) => `<b>${content}</b>`);
  result = renderDelimitedInlineStyle(result, "__", (content) => `<b>${content}</b>`);
  result = renderDelimitedInlineStyle(result, "*", (content) => `<i>${content}</i>`);
  return renderDelimitedInlineStyle(result, "_", (content) => `<i>${content}</i>`);
}

function restoreInlineMarkdownTokens(text: string, state: InlineMarkdownTokenState): string {
  return text.replace(
    /\uE000(\d+)\uE001/g,
    (_match, index: string) => state.tokens[Number(index)] ?? "",
  );
}

function renderInlineMarkdown(text: string): string {
  const tokenState: InlineMarkdownTokenState = { tokens: [] };
  let result = stashInlineMarkdownLinks(text, tokenState);
  result = stashInlineMarkdownCodeSpans(result, tokenState);
  result = escapeHtml(result);
  result = applyInlineMarkdownStyles(result);
  result = result.replace(/\\([\\`*_{}\[\]()#+\-.!>~|])/g, "$1");
  return restoreInlineMarkdownTokens(result, tokenState);
}

function renderMarkdownTextPiece(piece: string): string {
  const heading = matchMarkdownHeadingLine(piece);
  if (heading) {
    return `<b>${renderInlineMarkdown(heading[2] ?? "")}</b>`;
  }
  const task = piece.match(/^(\s*)([-*+]|\d+\.)\s+\[([ xX])\]\s+(.+)$/);
  if (task) {
    const checkboxMarker = (task[3] ?? " ").toLowerCase() === "x" ? "[x]" : "[ ]";
    return `<code>${checkboxMarker}</code> ${renderInlineMarkdown(task[4] ?? "")}`;
  }
  const bullet = piece.match(/^(\s*)[-*+]\s+(.+)$/);
  if (bullet) {
    return `<code>-</code> ${renderInlineMarkdown(bullet[2] ?? "")}`;
  }
  const numbered = piece.match(/^(\s*)(\d+)\.\s+(.+)$/);
  if (numbered) {
    return `<code>${numbered[2]}.</code> ${renderInlineMarkdown(numbered[3] ?? "")}`;
  }
  const quote = piece.match(/^>\s?(.+)$/);
  if (quote) {
    return `<blockquote>${renderInlineMarkdown(quote[1] ?? "")}</blockquote>`;
  }
  if (/^([-*_]\s*){3,}$/.test(piece.trim())) return "────────────";
  return renderInlineMarkdown(piece);
}

function renderMarkdownTextLines(block: string): string[] {
  const rendered: string[] = [];
  const lines = block.split("\n");
  for (const line of lines) {
    if (line.trim().length === 0) continue;
    rendered.push(renderMarkdownTextPiece(line));
  }
  return rendered;
}

function sanitizeTelegramCodeLanguage(language: string): string {
  return language.split(/\s+/)[0]?.replace(/[^A-Za-z0-9_+.-]/g, "") ?? "";
}

function renderMarkdownCodeBlock(code: string, language?: string): string[] {
  const safeLanguage = language ? sanitizeTelegramCodeLanguage(language) : "";
  const open = safeLanguage
    ? `<pre><code class="language-${escapeHtmlAttribute(safeLanguage)}">`
    : "<pre><code>";
  const close = "</code></pre>";
  const maxContentLength = MAX_MESSAGE_LENGTH - open.length - close.length;
  const chunks: string[] = [];
  let current = "";
  const pushCurrent = (): void => {
    if (current.length === 0) return;
    chunks.push(`${open}${current}${close}`);
    current = "";
  };
  const appendEscapedLine = (escapedLine: string): void => {
    if (escapedLine.length <= maxContentLength) {
      const candidate = current.length === 0 ? escapedLine : `${current}\n${escapedLine}`;
      if (candidate.length <= maxContentLength) {
        current = candidate;
        return;
      }
      pushCurrent();
      current = escapedLine;
      return;
    }
    pushCurrent();
    for (let i = 0; i < escapedLine.length; i += maxContentLength) {
      chunks.push(`${open}${escapedLine.slice(i, i + maxContentLength)}${close}`);
    }
  };
  for (const line of code.split("\n")) {
    appendEscapedLine(escapeHtml(line));
  }
  pushCurrent();
  return chunks.length > 0 ? chunks : [`${open}${close}`];
}

function isMarkdownTableSeparator(line: string): boolean {
  return /^\s*\|?(?:\s*:?-{3,}:?\s*\|)+\s*:?-{3,}:?\s*\|?\s*$/.test(line);
}

function parseMarkdownTableRow(line: string): string[] {
  const trimmed = line.trim().replace(/^\|/, "").replace(/\|$/, "");
  return trimmed.split("|").map((cell) => stripInlineMarkdownToPlainText(cell.trim()));
}

function getTelegramTableGraphemes(text: string): string[] {
  if (typeof Intl.Segmenter === "function") {
    const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
    return Array.from(segmenter.segment(text), (segment) => segment.segment);
  }
  return Array.from(text);
}

function isTelegramTableEmojiGrapheme(grapheme: string): boolean {
  return /\p{Extended_Pictographic}|\p{Emoji_Presentation}|\p{Regional_Indicator}/u.test(grapheme) || grapheme.includes("\u20e3");
}

function getTelegramTableCodePointWidth(char: string): number {
  const codePoint = char.codePointAt(0) ?? 0;
  if (codePoint === 0 || codePoint < 32) return 0;
  if (/\p{Mark}/u.test(char)) return 0;
  if ((codePoint >= 0xfe00 && codePoint <= 0xfe0f) || codePoint === 0x200d) return 0;
  if (
    (codePoint >= 0x1100 && codePoint <= 0x115f) ||
    codePoint === 0x2329 || codePoint === 0x232a ||
    (codePoint >= 0x2e80 && codePoint <= 0xa4cf) ||
    (codePoint >= 0xac00 && codePoint <= 0xd7a3) ||
    (codePoint >= 0xf900 && codePoint <= 0xfaff) ||
    (codePoint >= 0xfe10 && codePoint <= 0xfe19) ||
    (codePoint >= 0xfe30 && codePoint <= 0xfe6f) ||
    (codePoint >= 0xff00 && codePoint <= 0xff60) ||
    (codePoint >= 0xffe0 && codePoint <= 0xffe6)
  ) {
    return 2;
  }
  return 1;
}

function getTelegramTableCellWidth(text: string): number {
  return getTelegramTableGraphemes(text).reduce((width, grapheme) => {
    if (isTelegramTableEmojiGrapheme(grapheme)) return width + 2;
    return width + Array.from(grapheme).reduce((sum, char) => sum + getTelegramTableCodePointWidth(char), 0);
  }, 0);
}

function padTelegramTableCellEnd(cell: string, width: number): string {
  const padding = width - getTelegramTableCellWidth(cell);
  return padding > 0 ? `${cell}${" ".repeat(padding)}` : cell;
}

function renderMarkdownTableBlock(lines: string[]): string[] {
  const rows = lines.map(parseMarkdownTableRow);
  const columnCount = Math.max(...rows.map((row) => row.length), 0);
  const normalizedRows = rows.map((row) => {
    const next = [...row];
    while (next.length < columnCount) next.push("");
    return next;
  });
  const widths = Array.from({ length: columnCount }, (_, columnIndex) => {
    return Math.max(3, ...normalizedRows.map((row) => getTelegramTableCellWidth(row[columnIndex] ?? "")));
  });
  const formatRow = (row: string[]): string => {
    return row.map((cell, columnIndex) => padTelegramTableCellEnd(cell ?? "", widths[columnIndex] ?? 3)).join(" | ");
  };
  const separator = widths.map((width) => "-".repeat(width)).join(" | ");
  const [header, ...body] = normalizedRows;
  const tableLines = [formatRow(header ?? []), separator, ...body.map(formatRow)];
  return renderMarkdownCodeBlock(tableLines.join("\n"), "markdown");
}

function chunkRenderedHtmlLines(lines: string[], wrapper?: { open: string; close: string }): string[] {
  if (lines.length === 0) return [];
  const open = wrapper?.open ?? "";
  const close = wrapper?.close ?? "";
  const maxContentLength = MAX_MESSAGE_LENGTH - open.length - close.length;
  const chunks: string[] = [];
  let current = "";
  const pushCurrent = (): void => {
    if (current.length === 0) return;
    chunks.push(`${open}${current}${close}`);
    current = "";
  };
  for (const line of lines) {
    const candidate = current.length === 0 ? line : `${current}\n${line}`;
    if (candidate.length <= maxContentLength) {
      current = candidate;
      continue;
    }
    pushCurrent();
    if (line.length <= maxContentLength) {
      current = line;
      continue;
    }
    for (let i = 0; i < line.length; i += maxContentLength) {
      chunks.push(`${open}${line.slice(i, i + maxContentLength)}${close}`);
    }
  }
  pushCurrent();
  return chunks;
}

function renderMarkdownTextBlock(block: string): string[] {
  return chunkRenderedHtmlLines(renderMarkdownTextLines(block));
}

function renderMarkdownQuoteBlock(lines: string[]): string[] {
  const inner = lines.map((line) => {
    const match = line.match(/^\s*((?:>\s*)+)(.*)$/);
    if (!match) return line;
    const depth = (match[1].match(/>/g) ?? []).length;
    const nestedIndent = "\u00A0".repeat(Math.max(0, depth - 1) * 2);
    return `${nestedIndent}${match[2] ?? ""}`;
  }).join("\n");
  return chunkRenderedHtmlLines(renderMarkdownTextLines(inner), { open: "<blockquote>", close: "</blockquote>" });
}

function parseMarkdownFence(line: string): { marker: "`" | "~"; length: number; info?: string } | undefined {
  const match = line.match(/^(\s*)([`~]{3,})(.*)$/);
  if (!match) return undefined;
  const fence = match[2] ?? "";
  const marker = fence[0] as "`" | "~";
  if ((marker !== "`" && marker !== "~") || /[^`~]/.test(fence)) {
    return undefined;
  }
  if (!fence.split("").every((char) => char === marker)) return undefined;
  return { marker, length: fence.length, info: (match[3] ?? "").trim() || undefined };
}

function isMatchingMarkdownFence(line: string, fence: { marker: "`" | "~"; length: number }): boolean {
  const match = line.match(/^(\s*)([`~]{3,})\s*$/);
  if (!match) return false;
  const candidate = match[2] ?? "";
  return (
    candidate.length >= fence.length &&
    candidate[0] === fence.marker &&
    candidate.split("").every((char) => char === fence.marker)
  );
}

function isFencedCodeStart(line: string): boolean {
  return parseMarkdownFence(line) !== undefined;
}

interface TelegramRenderedBlockWithSpacing {
  text: string;
  blankLinesBefore: number;
}

function collectFencedMarkdownCodeLines(lines: string[], index: number, fence: { marker: "`" | "~"; length: number }): { codeLines: string[]; nextIndex: number; closed: boolean } {
  const codeLines: string[] = [];
  let nextIndex = index + 1;
  while (nextIndex < lines.length && !isMatchingMarkdownFence(lines[nextIndex] ?? "", fence)) {
    codeLines.push(lines[nextIndex] ?? "");
    nextIndex += 1;
  }
  const closed = nextIndex < lines.length;
  if (closed) nextIndex += 1;
  return { codeLines, nextIndex, closed };
}

function collectMarkdownTableBlockLines(lines: string[], index: number): { tableLines: string[]; nextIndex: number } {
  const tableLines = [lines[index] ?? ""];
  let nextIndex = index + 2;
  while (nextIndex < lines.length) {
    const tableLine = lines[nextIndex] ?? "";
    if (tableLine.trim().length === 0 || !tableLine.includes("|")) break;
    tableLines.push(tableLine);
    nextIndex += 1;
  }
  return { tableLines, nextIndex };
}

function collectQuoteBlockLines(lines: string[], index: number): { quoteLines: string[]; nextIndex: number } {
  const quoteLines: string[] = [];
  let nextIndex = index;
  while (nextIndex < lines.length && /^\s*>/.test(lines[nextIndex] ?? "")) {
    quoteLines.push(lines[nextIndex] ?? "");
    nextIndex += 1;
  }
  return { quoteLines, nextIndex };
}

function isMarkdownTextBlockBoundary(lines: string[], index: number): boolean {
  const current = lines[index] ?? "";
  const following = lines[index + 1] ?? "";
  if (current.trim().length === 0) return true;
  if (isFencedCodeStart(current)) return true;
  if (current.includes("|") && isMarkdownTableSeparator(following)) return true;
  return /^\s*>/.test(current);
}

function collectMarkdownTextBlockLines(lines: string[], index: number): { textLines: string[]; nextIndex: number } {
  const textLines: string[] = [];
  let nextIndex = index;
  while (nextIndex < lines.length) {
    if (isMarkdownTextBlockBoundary(lines, nextIndex)) break;
    textLines.push(lines[nextIndex] ?? "");
    nextIndex += 1;
  }
  return { textLines, nextIndex };
}

function renderMarkdownDocumentBlocks(normalizedMarkdown: string): TelegramRenderedBlockWithSpacing[] {
  const renderedBlocks: TelegramRenderedBlockWithSpacing[] = [];
  let minimumBlankLinesBeforeNextBlock = 0;
  const pushRenderedBlocks = (blocks: string[], blankLinesBefore: number): void => {
    const effectiveBlankLinesBefore = renderedBlocks.length === 0 ? blankLinesBefore : Math.max(blankLinesBefore, minimumBlankLinesBeforeNextBlock);
    for (const [blockIndex, block] of blocks.entries()) {
      renderedBlocks.push({ text: block, blankLinesBefore: blockIndex === 0 ? effectiveBlankLinesBefore : 0 });
    }
    minimumBlankLinesBeforeNextBlock = 0;
  };
  const lines = normalizedMarkdown.split("\n");
  let index = 0;
  let pendingBlankLines = 0;
  while (index < lines.length) {
    const line = lines[index] ?? "";
    const nextLine = lines[index + 1] ?? "";
    if (line.trim().length === 0) {
      pendingBlankLines += 1;
      index += 1;
      continue;
    }
    const heading = matchMarkdownHeadingLine(line);
    if (heading) {
      pushRenderedBlocks(renderMarkdownTextBlock(line), renderedBlocks.length === 0 ? pendingBlankLines : Math.max(pendingBlankLines, 1));
      pendingBlankLines = 0;
      minimumBlankLinesBeforeNextBlock = 1;
      index += 1;
      continue;
    }
    const fence = parseMarkdownFence(line);
    if (fence) {
      const block = collectFencedMarkdownCodeLines(lines, index, fence);
      index = block.nextIndex;
      pushRenderedBlocks(renderMarkdownCodeBlock(block.codeLines.join("\n"), fence.info), pendingBlankLines);
      pendingBlankLines = 0;
      continue;
    }
    if (line.includes("|") && isMarkdownTableSeparator(nextLine)) {
      const block = collectMarkdownTableBlockLines(lines, index);
      index = block.nextIndex;
      pushRenderedBlocks(renderMarkdownTableBlock(block.tableLines), pendingBlankLines);
      pendingBlankLines = 0;
      continue;
    }
    if (/^\s*>/.test(line)) {
      const block = collectQuoteBlockLines(lines, index);
      index = block.nextIndex;
      pushRenderedBlocks(renderMarkdownQuoteBlock(block.quoteLines), pendingBlankLines);
      pendingBlankLines = 0;
      continue;
    }
    const block = collectMarkdownTextBlockLines(lines, index);
    index = block.nextIndex;
    pushRenderedBlocks(renderMarkdownTextBlock(block.textLines.join("\n")), pendingBlankLines);
    pendingBlankLines = 0;
  }
  return renderedBlocks;
}

function chunkTelegramRenderedMarkdownBlocks(renderedBlocks: TelegramRenderedBlockWithSpacing[]): string[] {
  const chunks: string[] = [];
  let current = "";
  const flushCurrent = (): void => {
    if (current.length === 0) return;
    chunks.push(current);
    current = "";
  };
  for (const block of renderedBlocks) {
    const separator = "\n".repeat(block.blankLinesBefore + 1);
    const candidate = current.length === 0 ? block.text : `${current}${separator}${block.text}`;
    if (candidate.length <= MAX_MESSAGE_LENGTH) {
      current = candidate;
      continue;
    }
    flushCurrent();
    if (block.text.length <= MAX_MESSAGE_LENGTH) {
      current = block.text;
      continue;
    }
    for (let i = 0; i < block.text.length; i += MAX_MESSAGE_LENGTH) {
      chunks.push(block.text.slice(i, i + MAX_MESSAGE_LENGTH));
    }
  }
  flushCurrent();
  return chunks;
}

function renderMarkdownToTelegramHtmlChunks(markdown: string): string[] {
  const normalized = normalizeMarkdownDocument(markdown);
  if (normalized.length === 0) return [];
  return chunkTelegramRenderedMarkdownBlocks(renderMarkdownDocumentBlocks(normalized));
}

function chunkParagraphs(text: string): string[] {
  if (text.length <= MAX_MESSAGE_LENGTH) return [text];
  const normalized = text.replace(/\r\n/g, "\n");
  const paragraphs = normalized.split(/\n\n+/);
  const chunks: string[] = [];
  let current = "";
  const flushCurrent = (): void => {
    if (current.trim().length > 0) chunks.push(current);
    current = "";
  };
  const splitLongBlock = (block: string): string[] => {
    if (block.length <= MAX_MESSAGE_LENGTH) return [block];
    const lines = block.split("\n");
    const lineChunks: string[] = [];
    let lineCurrent = "";
    for (const line of lines) {
      const candidate = lineCurrent.length === 0 ? line : `${lineCurrent}\n${line}`;
      if (candidate.length <= MAX_MESSAGE_LENGTH) {
        lineCurrent = candidate;
        continue;
      }
      if (lineCurrent.length > 0) {
        lineChunks.push(lineCurrent);
        lineCurrent = "";
      }
      if (line.length <= MAX_MESSAGE_LENGTH) {
        lineCurrent = line;
        continue;
      }
      for (let i = 0; i < line.length; i += MAX_MESSAGE_LENGTH) {
        lineChunks.push(line.slice(i, i + MAX_MESSAGE_LENGTH));
      }
    }
    if (lineCurrent.length > 0) lineChunks.push(lineCurrent);
    return lineChunks;
  };
  for (const paragraph of paragraphs) {
    if (paragraph.length === 0) continue;
    const parts = splitLongBlock(paragraph);
    for (const part of parts) {
      const candidate = current.length === 0 ? part : `${current}\n\n${part}`;
      if (candidate.length <= MAX_MESSAGE_LENGTH) {
        current = candidate;
      } else {
        flushCurrent();
        current = part;
      }
    }
  }
  flushCurrent();
  return chunks;
}

type TelegramRenderMode = "plain" | "markdown" | "html";

interface TelegramRenderedChunk {
  text: string;
  parseMode?: "HTML";
}

function renderTelegramMessage(text: string, options?: { mode?: TelegramRenderMode }): TelegramRenderedChunk[] {
  const mode = options?.mode ?? "plain";
  if (mode === "plain") {
    return chunkParagraphs(text).map((chunk) => ({ text: chunk }));
  }
  if (mode === "html") {
    return chunkHtmlPreservingTags(text, MAX_MESSAGE_LENGTH).map((chunk) => ({ text: chunk, parseMode: "HTML" }));
  }
  return renderMarkdownToTelegramHtmlChunks(text).map((chunk) => ({ text: chunk, parseMode: "HTML" }));
}

function renderMarkdownPreviewText(markdown: string): string {
  const normalized = normalizeMarkdownDocument(markdown);
  if (normalized.length === 0) return "";
  const output: string[] = [];
  const lines = normalized.split("\n");
  let activeFence: { marker: "`" | "~"; length: number } | undefined;
  for (const rawLine of lines) {
    const line = rawLine ?? "";
    const fence = parseMarkdownFence(line);
    if (activeFence) {
      if (fence && isMatchingMarkdownFence(line, activeFence)) {
        activeFence = undefined;
        continue;
      }
      if (line.trim().length === 0) {
        output.push("");
        continue;
      }
      output.push(line);
      continue;
    }
    if (fence) {
      activeFence = { marker: fence.marker, length: fence.length };
      continue;
    }
    if (line.trim().length === 0) {
      output.push("");
      continue;
    }
    if (isMarkdownTableSeparator(line)) continue;
    const heading = matchMarkdownHeadingLine(line);
    if (heading) {
      output.push(stripInlineMarkdownToPlainText(heading[2] ?? ""));
      continue;
    }
    const task = line.match(/^(\s*)([-*+]|\d+\.)\s+\[([ xX])\]\s+(.+)$/);
    if (task) {
      const indent = " ".repeat((task[1] ?? "").length);
      const listMarker = task[2] ?? "-";
      const checkboxMarker = (task[3] ?? " ").toLowerCase() === "x" ? "[x]" : "[ ]";
      const taskPrefix = /^\d+\.$/.test(listMarker) ? `${listMarker} ${checkboxMarker}` : checkboxMarker;
      output.push(`${indent}${taskPrefix} ${stripInlineMarkdownToPlainText(task[4] ?? "")}`);
      continue;
    }
    const bullet = line.match(/^(\s*)[-*+]\s+(.+)$/);
    if (bullet) {
      output.push(`${" ".repeat((bullet[1] ?? "").length)}- ${stripInlineMarkdownToPlainText(bullet[2] ?? "")}`);
      continue;
    }
    const numbered = line.match(/^(\s*\d+\.)\s+(.+)$/);
    if (numbered) {
      output.push(`${numbered[1]} ${stripInlineMarkdownToPlainText(numbered[2] ?? "")}`);
      continue;
    }
    const quote = line.match(/^\s*>\s?(.+)$/);
    if (quote) {
      output.push(`> ${stripInlineMarkdownToPlainText(quote[1] ?? "")}`);
      continue;
    }
    if (/^\s*([-*_]\s*){3,}\s*$/.test(line)) {
      output.push("────────");
      continue;
    }
    output.push(stripInlineMarkdownToPlainText(line));
  }
  return output.join("\n");
}


// ─── Queue ───────────────────────────────────────────────────────────

function createQueue() {
  let items: QueuedItem[] = [];
  let nextOrder = 0;
  return {
    getItems: () => items,
    setItems: (next: QueuedItem[]) => {
      items = next;
    },
    append: (item: Omit<QueuedItem, "id" | "priority"> & { priority?: number }) => {
      const id = `${Date.now()}-${++nextOrder}`;
      const priority = item.priority ?? 0;
      const fullItem: QueuedItem = { ...item, id, priority };
      // Insert by priority desc, then timestamp asc
      const idx = items.findIndex((i) => i.priority < priority);
      if (idx === -1) items.push(fullItem);
      else items.splice(idx, 0, fullItem);
      return fullItem;
    },
    remove: (id: string) => {
      items = items.filter((i) => i.id !== id);
    },
    promote: (id: string) => {
      const idx = items.findIndex((i) => i.id === id);
      if (idx <= 0) return;
      const item = items.splice(idx, 1)[0];
      item.priority += 1;
      const insertIdx = items.findIndex((i) => i.priority < item.priority);
      if (insertIdx === -1) items.push(item);
      else items.splice(insertIdx, 0, item);
    },
    demote: (id: string) => {
      const idx = items.findIndex((i) => i.id === id);
      if (idx < 0 || idx >= items.length - 1) return;
      const item = items.splice(idx, 1)[0];
      item.priority -= 1;
      const insertIdx = items.findIndex((i) => i.priority < item.priority);
      if (insertIdx === -1) items.push(item);
      else items.splice(insertIdx, 0, item);
    },
    shift: () => items.shift(),
    length: () => items.length,
    clear: () => {
      items = [];
    },
    peek: () => items[0],
  };
}

// ─── Outbound Hidden Block Parser ────────────────────────────────────

interface TelegramVoiceBlock {
  type: "voice";
  lang?: string;
  rate?: string;
  text: string;
}

interface TelegramButtonBlock {
  type: "button";
  label: string;
  prompt: string;
}

function parseHiddenBlocks(text: string): { text: string; voices: TelegramVoiceBlock[]; buttons: TelegramButtonBlock[] } {
  const voices: TelegramVoiceBlock[] = [];
  const buttons: TelegramButtonBlock[] = [];
  const lines = text.split("\n");
  const out: string[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const voiceMatch = line.match(/^<!--\s*telegram_voice\s*(.*)$/);
    const buttonMatch = line.match(/^<!--\s*telegram_button\s+label=(".*?")(.*)$/);
    if (voiceMatch) {
      const attrs = (voiceMatch[1] ?? "").replace(/-->\s*$/, "").trim();
      const lang = attrs.match(/lang=(\S+)/)?.[1];
      const rate = attrs.match(/rate=(\S+)/)?.[1];
      const bodyLines: string[] = [];
      i++;
      while (i < lines.length && lines[i].trim() !== "-->") {
        if (!lines[i].trim().startsWith("<!--")) bodyLines.push(lines[i]);
        i++;
      }
      if (lines[i]?.trim() === "-->") i++;
      voices.push({ type: "voice", lang, rate, text: bodyLines.join("\n").trim() });
      continue;
    }
    if (buttonMatch) {
      const label = JSON.parse(buttonMatch[1]) as string;
      const bodyLines: string[] = [];
      i++;
      while (i < lines.length && lines[i].trim() !== "-->") {
        bodyLines.push(lines[i]);
        i++;
      }
      if (lines[i]?.trim() === "-->") i++;
      buttons.push({ type: "button", label, prompt: bodyLines.join("\n").trim() });
      continue;
    }
    out.push(line);
    i++;
  }
  return { text: out.join("\n"), voices, buttons };
}

// ─── Extension ───────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  // Global unhandled rejection catcher for this extension
  process.on("unhandledRejection", (reason) => {
    logError("unhandledRejection:", reason);
  });

  const config = loadEnvConfig();
  if (!config) {
    // Silently disabled
    return;
  }

  let botToken = config.botToken;
  const botId = getBotIdFromToken(botToken);
  logInfo(`Bot ID: ${botId}`);
  let chatId = config.chatId;
  let allowedUserId: number | undefined = undefined; // Will be set on /start
  let botUsername = "";
  let botNumericId = 0;
  let lastUpdateId: number | undefined;
  let pollingPromise: Promise<void> | undefined;
  let pollingController: AbortController | undefined;
  let sessionId = "";
  let isConnected = false;
  let isShuttingDown = false;
  let heartbeatTimer: ReturnType<typeof setInterval> | undefined;
  let typingTimer: ReturnType<typeof setInterval> | undefined;

  const queue = createQueue();
  let activeTurn: ActiveTurn | undefined;
  let dispatchPending = false;
  let pendingAttachments: string[] = [];
  let isFinalizing = false;

  // ─── Turn Tracking ─────────────────────────────────────────────────

  let currentTurnSourceMsgId: number | undefined;
  let hasUsedToolThisTurn = false;
  let isSteering = false;

  // ─── Message Text Tracking ─────────────────────────────────────────

  const assistantTexts: string[] = [];

  // ─── Helpers ───────────────────────────────────────────────────────

  function updateStatus(_ctx: ExtensionContext, msg?: string) {
    const status = msg || (isConnected ? "connected" : "disconnected");
    logInfo(`${status}`);
  }

  function refreshEnvConfig(): TelegramConfig | undefined {
    const newToken = process.env.TELEGRAM_BOT_TOKEN;
    const newChatId = process.env.TELEGRAM_CHAT_ID
      ? Number(process.env.TELEGRAM_CHAT_ID)
      : undefined;
    if (!newToken) return undefined;
    return { botToken: newToken, chatId: newChatId };
  }

  async function stopTelegramSession(): Promise<void> {
    if (!isConnected) return;
    isShuttingDown = true;
    stopHeartbeat();
    pollingController?.abort();
    if (pollingPromise) {
      await pollingPromise.catch(() => undefined);
    }
    pollingPromise = undefined;
    pollingController = undefined;
    await releaseLock(botToken);
    isConnected = false;
    isShuttingDown = false;
  }

  async function startTelegramSession(ctx: ExtensionContext): Promise<boolean> {
    if (isConnected) return true;
    let lock = await acquireLock(botToken, chatId, allowedUserId);
    if (!lock.acquired && lock.existing) {
      await sleep(2000);
      lock = await acquireLock(botToken, chatId, allowedUserId);
    }
    if (!lock.acquired && lock.existing) {
      logInfo(
        `Bot ${botId} polling by live PID ${lock.existing.pid} (updated ${Math.round((Date.now() - lock.existing.ts) / 1000)}s ago).`,
      );
      return false;
    }

    const me = await getMe(botToken);
    if (me) {
      botUsername = me.username;
      botNumericId = me.id;
    }

    await deleteWebhook(botToken);
    isShuttingDown = false;
    isConnected = true;
    updateStatus(ctx, "connected (reload)");
    if (ctx.hasUI) {
      ctx.ui.setStatus("telegram", "🟢 Telegram");
    }
    startHeartbeat();
    pollingController = new AbortController();
    pollingPromise = pollLoop(ctx);
    return true;
  }

  function getSessionId(ctx: ExtensionContext): string {
    if (sessionId) return sessionId;
    const sf = ctx.sessionManager.getSessionFile();
    sessionId = sf ? basename(sf, ".jsonl") : `pid-${process.pid}-${Date.now()}`;
    return sessionId;
  }

  async function ensureChatId(ctx: ExtensionContext): Promise<number | undefined> {
    if (chatId) return chatId;
    // If env TELEGRAM_CHAT_ID is not set, wait for /start
    return undefined;
  }

  // ─── Polling ───────────────────────────────────────────────────────

  async function pollLoop(ctx: ExtensionContext): Promise<void> {
    while (!isShuttingDown) {
      try {
        const updates = await getUpdates(botToken, {
          offset: lastUpdateId !== undefined ? lastUpdateId + 1 : undefined,
          limit: 10,
          timeout: 30,
          allowed_updates: ["message", "edited_message", "callback_query", "message_reaction"],
          signal: pollingController?.signal,
        });
        for (const upd of updates) {
          lastUpdateId = upd.update_id;
          await handleUpdate(upd, ctx);
        }
      } catch (err) {
        if (isShuttingDown) return;
        const errStr = String(err);
        if (errStr.includes("409 Conflict")) {
          logError(`Bot ${botId} 409 Conflict — another poller active. Backing off 15s...`);
          await sleep(15_000);
          continue;
        }
        logError("poll error:", err);
        await sleep(5000);
      }
    }
  }

  function sleep(ms: number): Promise<void> {
    return new Promise((res) => setTimeout(res, ms));
  }

  const TELEGRAM_COMMANDS = new Set([
    "/start",
    "/status",
    "/compact",
    "/abort",
    "/stop",
    "/continue",
    "/queue",
    "/next",
    "/help",
    "/model",
    "/reload",
  ]);

  function startHeartbeat() {
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    heartbeatTimer = setInterval(async () => {
      try {
        await updateLock(botToken, { ts: Date.now() });
      } catch {
        // ignore heartbeat write failures
      }
    }, HEARTBEAT_INTERVAL_MS);
  }

  function stopHeartbeat() {
    if (heartbeatTimer) {
      clearInterval(heartbeatTimer);
      heartbeatTimer = undefined;
    }
  }

  function startTyping(chatId: number) {
    if (typingTimer) clearInterval(typingTimer);
    sendChatAction(botToken, chatId, "typing").catch(() => {});
    typingTimer = setInterval(() => {
      sendChatAction(botToken, chatId, "typing").catch(() => {});
    }, 4000);
  }

  function stopTyping() {
    if (typingTimer) {
      clearInterval(typingTimer);
      typingTimer = undefined;
    }
  }

  // ─── Update Handler ────────────────────────────────────────────────

  async function handleUpdate(upd: TelegramUpdate, ctx: ExtensionContext): Promise<void> {
    const msg = upd.message ?? upd.edited_message;
    if (msg) {
      await handleMessage(msg, ctx, !!upd.edited_message);
      return;
    }
    if (upd.callback_query) {
      await handleCallbackQuery(upd.callback_query, ctx);
      return;
    }
    if (upd.message_reaction) {
      await handleReaction(upd.message_reaction, ctx);
      return;
    }
  }

  async function handleMessage(msg: TelegramMessage, ctx: ExtensionContext, isEdit: boolean): Promise<void> {
    const userId = msg.from?.id;
    const cid = msg.chat.id;

    // Pairing on /start
    if (msg.text?.startsWith("/start")) {
      if (!chatId) {
        chatId = cid;
        if (userId) allowedUserId = userId;
        await updateLock(botToken, { chatId, allowedUserId });
        await setMyCommands(botToken, [
          { command: "start", description: "Show status and controls" },
          { command: "status", description: "Show session status, model, and usage" },
          { command: "model", description: "Change model and thinking level" },
          { command: "compact", description: "Compact session context" },
          { command: "abort", description: "Abort current run" },
          { command: "stop", description: "Abort and clear queue" },
          { command: "continue", description: "Send continue prompt" },
          { command: "queue", description: "Show message queue" },
          { command: "reload", description: "Reload extensions and re-check env" },
          { command: "help", description: "Show available commands" },
        ]);
        await sendMessage(botToken, cid, "✅ Connected to Pi session. Send messages or files to interact.");
      } else if (cid === chatId) {
        await sendMessage(botToken, cid, "ℹ️ Already connected to this Pi session.");
      } else {
        await sendMessage(botToken, cid, "❌ This bot is already paired to another chat.");
      }
      return;
    }

    // Authorization
    if (chatId && cid !== chatId) return;
    if (allowedUserId && userId !== allowedUserId) return;

    // Slash commands from Telegram
    if (msg.text?.startsWith("/")) {
      const rawCmd = msg.text.split(" ")[0].split("@")[0];
      if (TELEGRAM_COMMANDS.has(rawCmd)) {
        await handleTelegramCommand(msg, ctx);
        return;
      }
      // Unknown command: pass through to Pi with [telegram] tag inserted after command
      const match = msg.text.match(/^(\/\S+)(\s+.*)?$/);
      if (match) {
        const [, cmd, rest] = match;
        msg.text = `${cmd} [telegram]${rest ?? ""}`;
      }
    } else {
      // Non-command message: prefix with [telegram]
      const text = msg.text ?? msg.caption;
      if (text) {
        const prefixed = `[telegram] ${text}`;
        if (msg.text) msg.text = prefixed;
        if (msg.caption) msg.caption = prefixed;
      }
    }

    // Build prompt text and files
    let promptText = msg.text ?? msg.caption ?? "";
    const images: Array<{ type: "image"; source: { type: "path"; path: string } }> = [];
    const files: string[] = [];
    const sid = getSessionId(ctx);

    // Photos
    if (msg.photo?.length) {
      // Always pick the largest photo by file_size for best quality
      const bestPhoto = msg.photo.reduce((a, b) => ((a.file_size ?? 0) > (b.file_size ?? 0) ? a : b));
      const path = await downloadTelegramFile(botToken, botId, cid, sid, bestPhoto.file_id, "photo.jpg");
      if (path) {
        const processed = await processImageFile(path);
        if (processed) {
          images.push({ type: "image", source: { type: "path", path: processed } });
        }
      }
    }

    // Video
    if (msg.video) {
      const path = await downloadTelegramFile(
        botToken, botId, cid, sid, msg.video.file_id,
        `video.${msg.video.mime_type?.split("/")[1] ?? "mp4"}`,
      );
      if (path) files.push(path);
    }

    // Document
    if (msg.document) {
      const isImage = msg.document.mime_type?.startsWith("image/");
      const path = await downloadTelegramFile(
        botToken, botId, cid, sid, msg.document.file_id,
        msg.document.file_name ?? "document",
      );
      if (path) {
        if (isImage) {
          const processed = await processImageFile(path);
          if (processed) {
            images.push({ type: "image", source: { type: "path", path: processed } });
          }
        } else {
          files.push(path);
        }
      }
    }

    // Voice / Audio
    if (msg.voice) {
      const path = await downloadTelegramFile(
        botToken, botId, cid, sid, msg.voice.file_id,
        `voice.${msg.voice.mime_type?.split("/")[1] ?? "ogg"}`,
      );
      if (path) files.push(path);
    }
    if (msg.audio) {
      const path = await downloadTelegramFile(
        botToken, botId, cid, sid, msg.audio.file_id,
        msg.audio.file_name ?? `audio.${msg.audio.mime_type?.split("/")[1] ?? "mp3"}`,
      );
      if (path) files.push(path);
    }

    // Reply context
    if (msg.reply_to_message) {
      const r = msg.reply_to_message;
      promptText = `[reply to message ${r.message_id}]\n${r.text ?? r.caption ?? ""}\n\n${promptText}`;
    }

    // Append file paths to prompt text
    for (const f of files) {
      promptText += `\n\n[File: ${f}]`;
    }

    if (!promptText.trim() && images.length === 0) return;

    const item: QueuedItem = {
      id: "",
      text: promptText.trim(),
      images: images.length ? images : undefined,
      files: files.length ? files : undefined,
      priority: 0,
      sourceMessageId: msg.message_id,
      chatId: cid,
      timestamp: Date.now(),
    };
    logInfo(`handleMessage: textLen=${item.text.length} images=${item.images?.length ?? 0} files=${item.files?.length ?? 0} sourceMsgId=${item.sourceMessageId} activeTurn=${activeTurn ? "yes" : "no"}`);

    if (isEdit) {
      // Update existing queued item from same message if present
      const existing = queue.getItems().find((i) => i.sourceMessageId === msg.message_id);
      if (existing) {
        existing.text = item.text;
        existing.images = item.images;
        existing.files = item.files;
        return;
      }
    }

    // Steering: if a turn is already active, send immediately as steer
    if (activeTurn) {
      isSteering = true;
      currentTurnSourceMsgId = msg.message_id;
      hasUsedToolThisTurn = false;

      await setMessageReaction(botToken, cid, msg.message_id, "🛞");

      // Build payload same as dispatchNext
      const contentParts: Array<
        | { type: "text"; text: string }
        | { type: "image"; source: { type: "base64"; media_type: string; data: string } }
      > = [];
      if (item.text?.trim()) contentParts.push({ type: "text", text: item.text.trim() });
      if (item.images?.length) {
        for (const img of item.images) {
          const base64Img = await imagePathToBase64Content(img.source.path);
          if (base64Img) contentParts.push(base64Img);
        }
      }
      const payload = contentParts.length === 1 && contentParts[0].type === "text"
        ? contentParts[0].text
        : contentParts;

      logInfo(`handleMessage: steering textLen=${item.text?.length ?? 0} images=${item.images?.length ?? 0}`);
      const result = pi.sendUserMessage(payload, { deliverAs: "steer" });
      if (result && typeof result.then === "function") {
        result.catch((err: unknown) => {
          logError("sendUserMessage steering rejected:", err);
        });
      }
      return;
    }

    queue.append(item);
    updateStatus(ctx, `queued (${queue.length()})`);
    await dispatchNext(ctx);
  }

  async function handleTelegramCommand(msg: TelegramMessage, ctx: ExtensionContext): Promise<void> {
    const cmd = msg.text!.split(" ")[0].split("@")[0];
    const cid = msg.chat.id;
    switch (cmd) {
      case "/status":
        await sendStatus(cid, ctx);
        break;
      case "/help":
        await sendHelp(cid);
        break;
      case "/model": {
        const models = ctx.modelRegistry.getAvailable().map((m) => ({
          id: `${m.provider}:${m.id}`,
          name: m.name,
          provider: m.provider,
        }));
        if (!models.length) {
          await sendMessage(botToken, cid, "❌ No models available.");
          break;
        }
        const keyboard = {
          inline_keyboard: models.map((m, idx) => [{
            text: `${m.name} (${m.provider})`,
            callback_data: `model:${idx}`,
          }]),
        };
        await tgFetch(botToken, "sendMessage", {
          chat_id: cid,
          text: "Select a model:",
          reply_markup: keyboard,
        });
        break;
      }
      case "/compact":
        if (ctx.isIdle()) {
          ctx.compact({});
          await sendMessage(botToken, cid, "🗜 Compacting...");
        } else {
          await sendMessage(botToken, cid, "⚠️ Session is busy.");
        }
        break;
      case "/abort":
        ctx.abort();
        await sendMessage(botToken, cid, "🛑 Aborted.");
        break;
      case "/stop":
        ctx.abort();
        queue.clear();
        await sendMessage(botToken, cid, "🛑 Aborted and queue cleared.");
        break;
      case "/continue":
        queue.append({ text: "continue", chatId: cid, sourceMessageId: msg.message_id, timestamp: Date.now(), priority: 1 });
        updateStatus(ctx, `queued continue`);
        await dispatchNext(ctx);
        break;
      case "/queue":
        await sendQueueStatus(cid);
        break;
      case "/next":
        ctx.abort();
        await dispatchNext(ctx);
        break;
      case "/reload": {
        await sendMessage(botToken, cid, "🔄 Reloading...");
        try {
          // Re-check env first
          const newConfig = refreshEnvConfig();
          if (!newConfig || !newConfig.botToken || !newConfig.chatId) {
            // Env missing — stop if running
            if (isConnected) {
              await stopTelegramSession();
              await sendMessage(botToken, cid, "🔴 Telegram session stopped — env TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID missing.");
            } else {
              await sendMessage(botToken, cid, "ℹ️ Telegram session already stopped — env missing.");
            }
          } else if (!isConnected) {
            // Env present but not connected — update config and start
            botToken = newConfig.botToken;
            chatId = newConfig.chatId;
            const started = await startTelegramSession(ctx);
            if (started) {
              await sendMessage(botToken, cid, "🟢 Telegram session started via /reload.");
            } else {
              await sendMessage(botToken, cid, "❌ Failed to start — another instance may be active.");
            }
          } else {
            // Already connected — update config if changed, then reload extensions
            if (newConfig.botToken !== botToken || newConfig.chatId !== chatId) {
              botToken = newConfig.botToken;
              chatId = newConfig.chatId;
            }
            // ExtensionCommandContext has reload(); ExtensionContext does not, but the runtime
            // object carries it in interactive mode. Cast to any to access it.
            const reloadFn = (ctx as any).reload as (() => Promise<void>) | undefined;
            if (reloadFn) {
              await reloadFn();
              await sendMessage(botToken, cid, "✅ Reload complete.");
            } else {
              await sendMessage(botToken, cid, "❌ Reload not available in this mode.");
            }
          }
        } catch (err) {
          logError("Reload failed:", err);
          await sendMessage(botToken, cid, `❌ Reload failed: ${err}`);
        }
        break;
      }
      default:
        await sendMessage(botToken, cid, "❓ Unknown command. Use /help for available commands.");
    }
  }

  async function handleCallbackQuery(q: TelegramUpdate["callback_query"], ctx: ExtensionContext): Promise<void> {
    if (!q?.data) return;
    const cid = q.message?.chat.id;
    if (!cid) return;
    if (chatId && cid !== chatId) return;

    await answerCallbackQuery(botToken, q.id);

    // Queue controls
    if (q.data.startsWith("queue:remove:")) {
      const id = q.data.slice("queue:remove:".length);
      queue.remove(id);
      await sendQueueStatus(cid);
      return;
    }
    if (q.data.startsWith("queue:promote:")) {
      const id = q.data.slice("queue:promote:".length);
      queue.promote(id);
      await sendQueueStatus(cid);
      return;
    }
    if (q.data === "queue:clear") {
      queue.clear();
      await sendQueueStatus(cid);
      return;
    }

    // Model selection
    if (q.data.startsWith("model:")) {
      const idx = Number(q.data.slice("model:".length));
      const models = ctx.modelRegistry.getAvailable();
      const model = models[idx];
      if (!model) {
        await sendMessage(botToken, cid, "❌ Model not found.");
        return;
      }
      const thinkingLevels: string[] = ["off", "minimal", "low", "medium", "high", "xhigh"];
      const keyboard = {
        inline_keyboard: thinkingLevels.map((lvl) => [{
          text: lvl,
          callback_data: `thinking:${idx}:${lvl}`,
        }]),
      };
      await tgFetch(botToken, "sendMessage", {
        chat_id: cid,
        text: `Selected <b>${escapeHtml(model.name)}</b>. Choose thinking level:`,
        parse_mode: "HTML",
        reply_markup: keyboard,
      });
      return;
    }

    // Thinking level selection
    if (q.data.startsWith("thinking:")) {
      const parts = q.data.split(":");
      const idx = Number(parts[1]);
      const level = parts[2];
      const models = ctx.modelRegistry.getAvailable();
      const model = models[idx];
      if (!model) {
        await sendMessage(botToken, cid, "❌ Model not found.");
        return;
      }
      const ok = await pi.setModel(model);
      if (!ok) {
        await sendMessage(botToken, cid, "❌ Failed to switch model (no API key?).");
        return;
      }
      pi.setThinkingLevel(level as any);
      const currentLevel = pi.getThinkingLevel();
      await sendMessage(botToken, cid, `✅ Model set to <b>${escapeHtml(model.name)}</b>\n💭 Thinking: <code>${escapeHtml(currentLevel)}</code>`, { parse_mode: "HTML" });
      return;
    }

    // Default: enqueue as prompt
    queue.append({ text: q.data, chatId: cid, timestamp: Date.now(), priority: 0 });
    await dispatchNext(ctx);
  }

  async function handleReaction(reaction: TelegramUpdate["message_reaction"], ctx: ExtensionContext): Promise<void> {
    if (!reaction?.new_reaction?.length) return;
    const emoji = reaction.new_reaction[0].emoji;
    const cid = reaction.chat.id;
    if (chatId && cid !== chatId) return;

    const promoteEmojis = ["👍", "⚡", "❤", "🕊", "🔥"];
    const removeEmojis = ["👎", "👻", "💔", "💩", "🗑"];

    if (promoteEmojis.includes(emoji)) {
      // Promote oldest queued item
      const items = queue.getItems();
      if (items.length > 1) {
        queue.promote(items[1].id);
        updateStatus(ctx, `promoted by reaction`);
      }
    } else if (removeEmojis.includes(emoji)) {
      const items = queue.getItems();
      if (items.length) {
        queue.remove(items[items.length - 1].id);
        updateStatus(ctx, `removed by reaction`);
      }
    }
  }

  // ─── Dispatch ──────────────────────────────────────────────────────

  async function dispatchNext(ctx: ExtensionContext): Promise<void> {
    if (dispatchPending) return;
    if (!ctx.isIdle()) return;
    if (activeTurn) return;

    const item = queue.shift();
    if (!item) return;

    dispatchPending = true;
    activeTurn = { chatId: item.chatId, sourceMessageId: item.sourceMessageId ?? 0 };
    updateStatus(ctx, "running");

    try {
      const opts: { deliverAs?: string } = {};
      if (item.priority > 0) opts.deliverAs = "steer";

      const contentParts: Array<
        | { type: "text"; text: string }
        | { type: "image"; source: { type: "base64"; media_type: string; data: string } }
      > = [];

      if (item.text?.trim()) {
        contentParts.push({ type: "text", text: item.text.trim() });
      }

      if (item.images?.length) {
        for (const img of item.images) {
          const base64Img = await imagePathToBase64Content(img.source.path);
          if (base64Img) contentParts.push(base64Img);
        }
      }

      if (contentParts.length === 0) {
        activeTurn = undefined;
        dispatchPending = false;
        setTimeout(() => dispatchNext(ctx), 100);
        return;
      }

      const payload = contentParts.length === 1 && contentParts[0].type === "text"
        ? contentParts[0].text
        : contentParts;

      logInfo(`dispatchNext: sending textLen=${item.text?.length ?? 0}, images=${item.images?.length ?? 0}, deliverAs=${opts.deliverAs ?? "default"}`);
      logInfo(`dispatchNext: payload=${JSON.stringify(payload).slice(0, 500)}`);
      const result = pi.sendUserMessage(payload, opts);
      if (result && typeof result.then === "function") {
        result.catch((err: unknown) => {
          logError("sendUserMessage rejected:", err);
        });
      }
    } catch (err) {
      logError("dispatch error:", err);
      activeTurn = undefined;
    } finally {
      dispatchPending = false;
    }
  }

  // ─── Status Messages ───────────────────────────────────────────────

  async function sendStatus(cid: number, ctx: ExtensionContext): Promise<void> {
    const usage = ctx.getContextUsage();
    const model = ctx.model;
    const currentModel = model ? `${model.name} (${model.provider})` : "none";
    const thinking = pi.getThinkingLevel();

    const lines = [
      `<b>Pi Telegram</b>`,
      ``,
      `Status: ${isConnected ? "🟢 connected" : "🔴 disconnected"}`,
      `Model: <code>${escapeHtml(currentModel)}</code>`,
      `Thinking: <code>${escapeHtml(thinking)}</code>`,
      `Queue: ${queue.length()}`,
      `Idle: ${ctx.isIdle() ? "yes" : "no"}`,
    ];

    if (usage) {
      if (usage.tokens !== null) {
        lines.push(`Context: ${usage.tokens.toLocaleString()} / ${usage.contextWindow.toLocaleString()} tokens (${usage.percent?.toFixed(1) ?? "?"}%)`);
      } else {
        lines.push(`Context: unknown / ${usage.contextWindow.toLocaleString()} tokens`);
      }
    }

    lines.push(`Session: <code>${sessionId}</code>`);

    await sendMessage(botToken, cid, lines.join("\n"), { parse_mode: "HTML" });
  }

  async function sendHelp(cid: number): Promise<void> {
    const lines = [
      `<b>Telegram Commands</b>`,
      ``,
      `<code>/start</code> — Connect to Pi session`,
      `<code>/status</code> — Show session status, model, and usage`,
      `<code>/model</code> — Change model and thinking level`,
      `<code>/compact</code> — Compact session context`,
      `<code>/continue</code> — Send continue prompt`,
      `<code>/queue</code> — Show message queue`,
      `<code>/next</code> — Skip current and run next queued item`,
      `<code>/reload</code> — Reload extensions and re-check env`,
      `<code>/abort</code> — Abort current run`,
      `<code>/stop</code> — Abort and clear queue`,
      `<code>/help</code> — Show this help`,
      ``,
      `Send messages or files to interact with Pi.`,
      `Reactions: 👍⚡❤ promote, 👎👻💔 remove.`,
    ];
    await sendMessage(botToken, cid, lines.join("\n"), { parse_mode: "HTML" });
  }

  async function sendQueueStatus(cid: number): Promise<void> {
    const items = queue.getItems();
    if (!items.length) {
      await sendMessage(botToken, cid, "📭 Queue is empty.");
      return;
    }
    const lines = items.map((item, idx) => {
      const short = escapeHtml(item.text.slice(0, 40).replace(/\n/g, " "));
      const more = item.text.length > 40 ? "…" : "";
      return `${idx + 1}. ${short}${more}`;
    });
    await sendMessage(botToken, cid, `<b>Queue (${items.length})</b>\n\n${lines.join("\n")}`, { parse_mode: "HTML" });
  }

  // ─── Outbound Reply ────────────────────────────────────────────────

  async function sendReply(text: string, ctx: ExtensionContext): Promise<void> {
    if (!chatId) return;
    const { text: cleanText, voices, buttons } = parseHiddenBlocks(text);

    // Send text / markdown
    const strippedCleanText = stripTrailingEllipsis(cleanText);
    if (strippedCleanText.trim()) {
      const chunks = renderTelegramMessage(strippedCleanText, { mode: "markdown" });
      logInfo(`sendReply: chunks=${chunks.length} textLen=${cleanText.length} last50="${cleanText.slice(-50)}"`);
      for (const [i, chunk] of chunks.entries()) {
        logInfo(`chunk[${i}]: len=${chunk.text.length} parseMode=${chunk.parseMode ?? "plain"} last30="${chunk.text.slice(-30)}"`);
      }
      logInfo(`sendReply: chunks=${chunks.length} textEnd="${strippedCleanText.slice(-30)}"`);
      const replyTo = activeTurn?.sourceMessageId;
      for (let i = 0; i < chunks.length; i++) {
        const chunk = chunks[i];
        const opts: { parse_mode?: string; reply_to_message_id?: number; disable_web_page_preview?: boolean } = {
          parse_mode: chunk.parseMode,
          ...(i === 0 && replyTo && replyTo > 0 ? { reply_to_message_id: replyTo } : {}),
          disable_web_page_preview: true,
        };
        await sendMessage(botToken, chatId, chunk.text, opts);
      }
    }

    // Send voice (as text fallback since we don't have TTS pipeline by default)
    for (const v of voices) {
      await sendMessage(botToken, chatId, `🔊 Voice: ${v.text.slice(0, 200)}${v.text.length > 200 ? "…" : ""}`);
    }

    // Send button prompt
    for (const b of buttons) {
      const keyboard = {
        inline_keyboard: [[{ text: b.label, callback_data: b.prompt }]],
      };
      await tgFetch(botToken, "sendMessage", {
        chat_id: chatId,
        text: b.prompt,
        reply_markup: keyboard,
      });
    }

    // Send pending attachments
    for (const path of pendingAttachments) {
      await sendAttachment(path);
    }
    pendingAttachments = [];
  }

  async function sendAttachment(filePath: string): Promise<void> {
    if (!chatId) return;
    const ext = filePath.split(".").pop()?.toLowerCase() || "";
    const mime = ext === "mp4" || ext === "mov" ? "video" : ext === "mp3" || ext === "ogg" || ext === "wav" ? "audio" : ext === "jpg" || ext === "jpeg" || ext === "png" || ext === "webp" || ext === "gif" ? "photo" : "document";
    await sendMessageMultipart(botToken, chatId, "", filePath, mime, {
      reply_to_message_id: activeTurn?.sourceMessageId,
    });
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────

  pi.on("session_start", (_event, ctx) => {
    const sid = getSessionId(ctx);
    setLogSession(sid);

    // Fire connect sequence in background — don't block Pi main thread
    // Telegram API calls (getMe, deleteWebhook, sendMessage) can be slow
    (async () => {
      // Ensure temp dir exists
      if (chatId) {
        await prepareTempDir(botId, chatId, sid);
      }

      // Auto-connect: acquire lock with retry for stale locks
      let lock = await acquireLock(botToken, chatId, allowedUserId);
      if (!lock.acquired && lock.existing) {
        await sleep(2000);
        lock = await acquireLock(botToken, chatId, allowedUserId);
      }
      if (!lock.acquired && lock.existing) {
        logInfo(
          `Bot ${botId} polling by live PID ${lock.existing.pid} (updated ${Math.round((Date.now() - lock.existing.ts) / 1000)}s ago). Run /telegram-connect to force take over.`,
        );
        return;
      }

      // Resolve bot identity
      const me = await getMe(botToken);
      if (me) {
        botUsername = me.username;
        botNumericId = me.id;
      }

      await deleteWebhook(botToken);
      isShuttingDown = false;
      isConnected = true;
      updateStatus(ctx, "connected (auto)");
      startHeartbeat();

      pollingController = new AbortController();
      pollingPromise = pollLoop(ctx);

      // Notify Telegram that Pi session has connected
      if (chatId) {
        await sendMessage(botToken, chatId, "🟢 Pi session connected. Ready to receive tasks.");
      }
    })().catch((err) => logError("session_start connect error:", err));
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    isShuttingDown = true;
    stopHeartbeat();
    stopTyping();
    pollingController?.abort();
    if (pollingPromise) {
      await pollingPromise.catch(() => undefined);
    }
    pollingPromise = undefined;
    pollingController = undefined;
    await releaseLock(botToken);
    isConnected = false;
    updateStatus(ctx, "disconnected");
    if (ctx.hasUI) {
      ctx.ui.setStatus("telegram", undefined);
    }

    // Notify Telegram that Pi session has disconnected
    if (chatId) {
      await sendMessage(botToken, chatId, "🔴 Pi session disconnected. Reconnect with /telegram-connect.");
    }
  });

  pi.on("message_end", async (event, ctx) => {
    if (event.message.role !== "assistant") return;
    const content = event.message.content;
    let text = "";
    if (typeof content === "string") {
      text = content;
    } else if (Array.isArray(content)) {
      text = content
        .map((c: any) => {
          if (c.type === "text" && c.text) return c.text;
          if (c.type === "text" && typeof c.content === "string") return c.content;
          return "";
        })
        .join("");
    } else if (content && typeof content.text === "string") {
      text = content.text;
    }
    if (text.trim()) {
      assistantTexts.push(text);
      logInfo(`message_end: captured textLen=${text.length}`);
    }
  });

  pi.on("agent_start", async (_event, ctx) => {
    if (!activeTurn) return;
    startTyping(activeTurn.chatId);
    assistantTexts.length = 0;

    // Track turn source message for reactions
    currentTurnSourceMsgId = activeTurn.sourceMessageId;
    hasUsedToolThisTurn = false;

    if (isSteering) {
      // Steering turn: 🛞 was already set on the steering message
      logInfo(`agent_start: steering turn sourceMsgId=${currentTurnSourceMsgId}`);
    } else if (currentTurnSourceMsgId && currentTurnSourceMsgId > 0) {
      // Normal new turn: 👀 eyes — bot received, LLM thinking
      logInfo(`agent_start: normal turn sourceMsgId=${currentTurnSourceMsgId}`);
      await setMessageReaction(botToken, activeTurn.chatId, currentTurnSourceMsgId, "👀");
    }
  });

  // Streaming preview removed — only send final result

  pi.on("tool_execution_start", async (event, ctx) => {
    if (!activeTurn || hasUsedToolThisTurn) return;
    hasUsedToolThisTurn = true;
    const msgId = isSteering ? currentTurnSourceMsgId : activeTurn.sourceMessageId;
    if (msgId && msgId > 0) {
      logInfo(`tool_execution_start: first tool, sourceMsgId=${msgId}`);
      await setMessageReaction(botToken, activeTurn.chatId, msgId, "⚙️");
    }
  });

  pi.on("agent_end", async (event, ctx) => {
    stopTyping();
    if (!activeTurn) return;
    isFinalizing = true;

    try {
      // Green checkmark on the message that triggered this turn
      const doneMsgId = isSteering ? currentTurnSourceMsgId : activeTurn.sourceMessageId;
      if (doneMsgId && doneMsgId > 0) {
        logInfo(`agent_end: done sourceMsgId=${doneMsgId} steering=${isSteering}`);
        await setMessageReaction(botToken, activeTurn.chatId, doneMsgId, "✅");
      }

      // Reset steering state for next turn
      if (isSteering) {
        isSteering = false;
        currentTurnSourceMsgId = undefined;
      }

      // Extract text from multiple sources
      let lastAssistantText = "";
      let source = "none";

      // 1. message_end tracking (most reliable)
      if (assistantTexts.length > 0) {
        lastAssistantText = assistantTexts[assistantTexts.length - 1];
        source = "message_end";
      }

      // 2. agent_end event.messages
      if (!lastAssistantText.trim() && event.messages?.length) {
        for (let i = event.messages.length - 1; i >= 0; i--) {
          const msg = event.messages[i];
          if (msg.role === "assistant") {
            const content = msg.content;
            if (typeof content === "string") {
              lastAssistantText = content;
            } else if (Array.isArray(content)) {
              lastAssistantText = content
                .map((c: any) => {
                  if (c.type === "text" && c.text) return c.text;
                  if (c.type === "text" && typeof c.content === "string") return c.content;
                  return "";
                })
                .join("");
            } else if (content && typeof content.text === "string") {
              lastAssistantText = content.text;
            }
            source = "event.messages";
            break;
          }
        }
      }

      // 3. session entries fallback
      if (!lastAssistantText.trim()) {
        const entries = ctx.sessionManager.getEntries();
        for (let i = entries.length - 1; i >= 0; i--) {
          const e = entries[i];
          if (e.role === "assistant") {
            const content = e.content;
            if (typeof content === "string") {
              lastAssistantText = content;
            } else if (Array.isArray(content)) {
              lastAssistantText = content
                .map((c: any) => {
                  if (c.type === "text" && c.text) return c.text;
                  if (c.type === "text" && typeof c.content === "string") return c.content;
                  return "";
                })
                .join("");
            } else if (content && typeof content.text === "string") {
              lastAssistantText = content.text;
            }
            source = "entries";
            break;
          }
        }
        logInfo(`agent_end: entries=${entries.length} textLen=${lastAssistantText.length} source=${source}`);
      } else {
        logInfo(`agent_end: textLen=${lastAssistantText.length} source=${source}`);
      }

      if (lastAssistantText.trim()) {
        const finalText = stripTrailingEllipsis(lastAssistantText);
        logInfo(`agent_end: sending reply textLen=${finalText.length}`);
        await sendReply(finalText, ctx);
      } else {
        logInfo("agent_end: no assistant text found, skipping reply");
      }

      activeTurn = undefined;
      updateStatus(ctx, "idle");

      // Dispatch next queued item after a short delay
      setTimeout(() => dispatchNext(ctx), 500);
    } catch (err) {
      logError("agent_end error:", err);
    } finally {
      isFinalizing = false;
    }
  });

  // ─── Commands ──────────────────────────────────────────────────────

  pi.registerCommand("telegram-connect", {
    description: "Connect Telegram bot polling (take over if needed)",
    handler: async (_args, ctx) => {
      if (isConnected) {
        ctx.ui.notify("Already connected", "info");
        return;
      }
      let lock = await acquireLock(botToken, chatId, allowedUserId);
      if (!lock.acquired && lock.existing) {
        const stale = isStale(lock.existing);
        const msg = stale
          ? `Lock is stale (PID ${lock.existing.pid}, ${Math.round((Date.now() - lock.existing.ts) / 1000)}s old). Take over?`
          : `Bot polling by live PID ${lock.existing.pid}. Take over?`;
        const ok = await ctx.ui.confirm("Take over?", msg);
        if (!ok) {
          ctx.ui.notify("Cancelled", "info");
          return;
        }
        // Force acquire
        const locks = await readLocks();
        locks[getBotIdFromToken(botToken)] = {
          pid: process.pid,
          ts: Date.now(),
          chatId,
          allowedUserId,
        };
        await writeLocks(locks);
      }
      await deleteWebhook(botToken);
      isShuttingDown = false;
      isConnected = true;
      updateStatus(ctx, "connected");
      if (ctx.hasUI) {
        ctx.ui.setStatus("telegram", "🟢 Telegram");
      }
      startHeartbeat();
      pollingController = new AbortController();
      pollingPromise = pollLoop(ctx);
      ctx.ui.notify("Telegram connected", "success");
    },
  });

  pi.registerCommand("telegram-disconnect", {
    description: "Disconnect Telegram bot polling",
    handler: async (_args, ctx) => {
      isShuttingDown = true;
      stopHeartbeat();
      stopTyping();
      pollingController?.abort();
      if (pollingPromise) {
        await pollingPromise.catch(() => undefined);
      }
      pollingPromise = undefined;
      pollingController = undefined;
      await releaseLock(botToken);
      isConnected = false;
      isShuttingDown = false;
      updateStatus(ctx, "disconnected");
      if (ctx.hasUI) {
        ctx.ui.setStatus("telegram", undefined);
      }
      ctx.ui.notify("Telegram disconnected", "info");
    },
  });

  pi.registerCommand("telegram-status", {
    description: "Show Telegram bridge status",
    handler: async (_args, ctx) => {
      const locks = await readLocks();
      const botKey = getBotIdFromToken(botToken);
      const lock = locks[botKey];
      const lines = [
        `Connected: ${isConnected ? "yes" : "no"}`,
        `Bot ID: ${botKey}`,
        `Chat ID: ${chatId ?? "not set"}`,
        `Queue: ${queue.length()}`,
        `Lock PID: ${lock?.pid ?? "none"}`,
        `Session: ${getSessionId(ctx)}`,
      ];
      ctx.ui.notify(lines.join(" | "), "info");
    },
  });

  // ─── Attachment Tool ───────────────────────────────────────────────

  pi.registerTool({
    name: "telegram_attach",
    label: "Attach to Telegram",
    description: "Queue a local file to be sent with the next Telegram reply",
    parameters: Type.Object({
      path: Type.String({ description: "Absolute path to the file to attach" }),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
      const p = params.path;
      if (!existsSync(p)) {
        return {
          content: [{ type: "text", text: `File not found: ${p}` }],
          isError: true,
        };
      }
      pendingAttachments.push(p);
      return {
        content: [{ type: "text", text: `Attached: ${basename(p)}` }],
      };
    },
  });
}
