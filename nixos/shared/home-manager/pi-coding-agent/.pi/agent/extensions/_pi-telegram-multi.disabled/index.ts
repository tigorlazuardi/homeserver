import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { existsSync } from "node:fs";
import {
  chmod,
  mkdir,
  readFile,
  rename,
  writeFile,
} from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { createHash } from "node:crypto";

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
      console.error(`[pi-telegram-multi] ${method} failed:`, json.description);
      return undefined;
    }
    return json.result;
  } catch (err) {
    console.error(`[pi-telegram-multi] ${method} error:`, err);
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
  const result = await tgFetch<TelegramUpdate[]>(botToken, "getUpdates", opts, opts.signal);
  return result ?? [];
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
      console.error("[pi-telegram-multi] multipart send failed:", json.description);
      return undefined;
    }
    return json.result;
  } catch (err) {
    console.error("[pi-telegram-multi] multipart send error:", err);
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

async function sendChatAction(botToken: string, chatId: number, action: string): Promise<void> {
  await tgFetch(botToken, "sendChatAction", { chat_id: chatId, action });
}

async function answerCallbackQuery(botToken: string, queryId: string, text?: string): Promise<void> {
  await tgFetch(botToken, "answerCallbackQuery", { callback_query_id: queryId, text });
}

async function setMyCommands(botToken: string, commands: Array<{ command: string; description: string }>): Promise<void> {
  await tgFetch(botToken, "setMyCommands", { commands });
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
    console.error("[pi-telegram-multi] download error:", err);
    return undefined;
  }
}

// ─── Markdown → Telegram HTML ────────────────────────────────────────

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function markdownToTelegramHtml(md: string): string {
  let html = md;
  // Code blocks
  html = html.replace(/```([\w]*)([\s\S]*?)```/g, (_m, lang, code) => {
    return `<pre><code class="language-${lang || "text"}">${escapeHtml(code.trim())}</code></pre>`;
  });
  // Inline code
  html = html.replace(/`([^`]+)`/g, "<code>$1</code>");
  // Bold
  html = html.replace(/\*\*(.+?)\*\*/g, "<b>$1</b>");
  // Italic
  html = html.replace(/__(.+?)__/g, "<i>$1</i>");
  // Strikethrough
  html = html.replace(/~~(.+?)~~/g, "<s>$1</s>");
  // Links [text](url)
  html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
  // Blockquote
  html = html.replace(/^>(.+)$/gm, "<blockquote>$1</blockquote>");
  // Lists
  html = html.replace(/^\s*[-*]\s+(.+)$/gm, "• $1");
  // Numbered lists
  html = html.replace(/^\s*\d+\.\s+(.+)$/gm, "$1");
  // Horizontal rule
  html = html.replace(/^---+$/gm, "");
  // Tables: crude strip
  html = html.replace(/\|?\s*:?---+:?\s*\|?/g, "");
  html = html.replace(/\|/g, " | ");
  // Trim consecutive newlines to max 2
  html = html.replace(/\n{3,}/g, "\n\n");
  return html;
}

function splitTelegramHtml(html: string, maxLen = 4000): string[] {
  if (html.length <= maxLen) return [html];
  const chunks: string[] = [];
  let remaining = html;
  while (remaining.length > maxLen) {
    let cut = remaining.lastIndexOf("\n\n", maxLen);
    if (cut < maxLen * 0.7) cut = remaining.lastIndexOf("\n", maxLen);
    if (cut < maxLen * 0.7) cut = remaining.lastIndexOf(" ", maxLen);
    if (cut <= 0) cut = maxLen;
    chunks.push(remaining.slice(0, cut));
    remaining = remaining.slice(cut).trimStart();
  }
  if (remaining) chunks.push(remaining);
  return chunks;
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
  const config = loadEnvConfig();
  if (!config) {
    // Silently disabled
    return;
  }

  const botToken = config.botToken;
  const botId = getBotIdFromToken(botToken);
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
  let previewMessageId: number | undefined;
  let previewText = "";
  let pendingAttachments: string[] = [];

  // ─── Helpers ───────────────────────────────────────────────────────

  function updateStatus(_ctx: ExtensionContext, msg?: string) {
    const status = msg || (isConnected ? "connected" : "disconnected");
    console.log(`[pi-telegram-multi] ${status}`);
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
        console.error("[pi-telegram-multi] poll error:", err);
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
      const largest = msg.photo.reduce((a, b) =>
        (a.file_size ?? 0) > (b.file_size ?? 0) ? a : b,
      );
      const path = await downloadTelegramFile(botToken, botId, cid, sid, largest.file_id, "photo.jpg");
      if (path) {
        images.push({ type: "image", source: { type: "path", path } });
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
      const path = await downloadTelegramFile(
        botToken, botId, cid, sid, msg.document.file_id,
        msg.document.file_name ?? "document",
      );
      if (path) files.push(path);
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
        text: `Selected <b>${model.name}</b>. Choose thinking level:`,
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
      await sendMessage(botToken, cid, `✅ Model set to <b>${model.name}</b>\n💭 Thinking: <code>${currentLevel}</code>`, { parse_mode: "HTML" });
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
      const content: Array<
        | { type: "text"; text: string }
        | { type: "image"; source: { type: "path"; path: string } }
      > = [];
      if (item.text) content.push({ type: "text", text: item.text });
      if (item.images?.length) content.push(...item.images);
      if (content.length === 0) {
        activeTurn = undefined;
        dispatchPending = false;
        setTimeout(() => dispatchNext(ctx), 100);
        return;
      }
      const opts: { deliverAs?: string } = {};
      if (item.priority > 0) opts.deliverAs = "steer";
      pi.sendUserMessage(content, opts);
    } catch (err) {
      console.error("[pi-telegram-multi] dispatch error:", err);
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
      `Model: <code>${currentModel}</code>`,
      `Thinking: <code>${thinking}</code>`,
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
      const short = item.text.slice(0, 40).replace(/\n/g, " ");
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
    if (cleanText.trim()) {
      const html = markdownToTelegramHtml(cleanText);
      const chunks = splitTelegramHtml(html);
      let replyTo = activeTurn?.sourceMessageId;
      for (let i = 0; i < chunks.length; i++) {
        const sent = await sendMessage(botToken, chatId, chunks[i], {
          parse_mode: "HTML",
          reply_to_message_id: i === 0 ? replyTo : undefined,
          disable_web_page_preview: true,
        });
        if (sent && i === 0 && chunks.length > 1) {
          replyTo = undefined; // Only reply to source on first chunk
        }
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

  // ─── Streaming Preview ─────────────────────────────────────────────

  async function updatePreview(text: string, ctx: ExtensionContext): Promise<void> {
    if (!chatId || !activeTurn) return;
    const html = markdownToTelegramHtml(text);
    if (previewMessageId) {
      // Try edit
      const ok = await editMessageText(botToken, chatId, previewMessageId, html + "…", { parse_mode: "HTML" });
      if (!ok) {
        // Message too old or changed, send new
        const sent = await sendMessage(botToken, chatId, html + "…", { parse_mode: "HTML" });
        if (sent) previewMessageId = sent.message_id;
      }
    } else {
      const sent = await sendMessage(botToken, chatId, html + "…", { parse_mode: "HTML" });
      if (sent) previewMessageId = sent.message_id;
    }
    previewText = text;
  }

  async function finalizePreview(finalText: string): Promise<void> {
    if (!chatId || !previewMessageId) return;
    const html = markdownToTelegramHtml(finalText);
    const ok = await editMessageText(botToken, chatId, previewMessageId, html, { parse_mode: "HTML" });
    if (!ok) {
      await sendMessage(botToken, chatId, html, { parse_mode: "HTML" });
    }
    previewMessageId = undefined;
    previewText = "";
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────

  pi.on("session_start", async (_event, ctx) => {
    const sid = getSessionId(ctx);
    // Ensure temp dir exists
    if (chatId) {
      await prepareTempDir(botId, chatId, sid);
    }

    // Auto-connect: acquire lock with retry for stale locks
    let lock = await acquireLock(botToken, chatId, allowedUserId);
    if (!lock.acquired && lock.existing) {
      // Wait briefly and retry once — the owner might be shutting down
      await sleep(2000);
      lock = await acquireLock(botToken, chatId, allowedUserId);
    }
    if (!lock.acquired && lock.existing) {
      console.log(
        `[pi-telegram-multi] Bot polling by live PID ${lock.existing.pid} (updated ${Math.round((Date.now() - lock.existing.ts) / 1000)}s ago). Run /telegram-connect to force take over.`,
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
  });

  pi.on("agent_start", async (_event, ctx) => {
    if (!activeTurn) return;
    // Clear preview state for new turn
    previewMessageId = undefined;
    previewText = "";
    startTyping(activeTurn.chatId);
  });

  pi.on("message_update", async (event, ctx) => {
    if (!activeTurn) return;
    const msg = event.message;
    if (msg.role !== "assistant") return;
    const text = msg.content
      ?.filter((c) => c.type === "text")
      .map((c) => ("text" in c ? c.text : ""))
      .join("")
      ?? "";
    // Only update preview if text grew meaningfully
    if (text.length > previewText.length + 20 || text.endsWith("\n")) {
      await updatePreview(text, ctx);
    }
  });

  pi.on("agent_end", async (_event, ctx) => {
    stopTyping();
    if (!activeTurn) return;

    // Find last assistant message
    const entries = ctx.sessionManager.getEntries();
    let lastAssistantText = "";
    for (let i = entries.length - 1; i >= 0; i--) {
      const e = entries[i];
      if (e.role === "assistant") {
        lastAssistantText =
          e.content
            ?.filter((c) => c.type === "text")
            .map((c) => ("text" in c ? c.text : ""))
            .join("") ?? "";
        break;
      }
    }

    if (lastAssistantText) {
      await finalizePreview(lastAssistantText);
      await sendReply(lastAssistantText, ctx);
    }

    activeTurn = undefined;
    updateStatus(ctx, "idle");

    // Dispatch next queued item after a short delay
    setTimeout(() => dispatchNext(ctx), 500);
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
      ctx.ui.notify("Telegram disconnected", "info");
    },
  });

  pi.registerCommand("telegram-status", {
    description: "Show Telegram bridge status",
    handler: async (_args, ctx) => {
      const locks = await readLocks();
      const hash = getBotIdFromToken(botToken);
      const lock = locks[hash];
      const lines = [
        `Connected: ${isConnected ? "yes" : "no"}`,
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
