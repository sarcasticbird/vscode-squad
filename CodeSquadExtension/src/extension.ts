import * as vscode from "vscode";
import * as http from "http";
import * as crypto from "crypto";

const PORT = 9876;
const BASE = `http://127.0.0.1:${PORT}`;

interface RemoteClaudeSession {
  pid: string;
  cwd: string;
  status: string | null;
  sessionId: string | null;
  source: string;
  chatTitle: string | null;
}

interface WorkspacePayload {
  windowId: string;
  workspaceName: string;
  folderPaths: string[];
  workspaceFile: string | null;
  claudeInstalled: boolean;
  claudeActive: boolean;
  remoteAuthority: string | null;
  commandPort: number | null;
  commandToken: string | null;
  remoteSessions?: RemoteClaudeSession[];
  focused?: boolean;
}

let registered = false;
let outputChannel: vscode.OutputChannel;
let heartbeat: ReturnType<typeof setInterval> | undefined;
let commandServer: http.Server | undefined;
let commandPort: number | undefined;
const commandToken = crypto.randomUUID();

function getWindowId(): string {
  return vscode.env.sessionId;
}

function log(msg: string): void {
  outputChannel?.appendLine(`[${new Date().toISOString()}] ${msg}`);
}

function startCommandServer(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      const contentLength = parseInt(req.headers["content-length"] ?? "0", 10);
      if (contentLength > 1024) {
        req.destroy();
        return;
      }
      req.resume();
      if (req.method === "POST" && req.url === "/command/reload") {
        const auth = req.headers["authorization"];
        if (auth !== `Bearer ${commandToken}`) {
          res.writeHead(403, { "Content-Type": "text/plain" });
          res.end("forbidden");
          log("Rejected command: invalid token");
          return;
        }
        res.writeHead(200, { "Content-Type": "text/plain" });
        res.end("ok");
        log("Received reload window command");
        setTimeout(() => vscode.commands.executeCommand("workbench.action.reloadWindow"), 100);
        return;
      }
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("not found");
    });

    server.listen(0, "127.0.0.1", () => {
      const addr = server.address();
      if (addr && typeof addr !== "string") {
        commandServer = server;
        commandPort = addr.port;
        log(`Command server listening on 127.0.0.1:${addr.port}`);
        resolve(addr.port);
      } else {
        reject(new Error("Failed to bind command server"));
      }
    });

    server.on("error", reject);
  });
}

function buildPayload(): WorkspacePayload {
  const folders = (vscode.workspace.workspaceFolders ?? []).map(
    (f) => f.uri.fsPath
  );
  const claudeExt = vscode.extensions.getExtension("anthropic.claude-code");

  const wsFile = vscode.workspace.workspaceFile;
  const workspaceFile = wsFile?.scheme === "file" ? wsFile.fsPath : null;

  const workspaceName =
    vscode.workspace.name ?? folders[0]?.split("/").pop() ?? "Unknown";

  return {
    windowId: getWindowId(),
    workspaceName,
    folderPaths: folders,
    workspaceFile,
    claudeInstalled: claudeExt !== undefined,
    claudeActive: claudeExt?.isActive ?? false,
    remoteAuthority: (vscode.workspace.workspaceFolders ?? [])[0]?.uri.authority || null,
    commandPort: commandPort ?? null,
    commandToken: commandPort ? commandToken : null,
  };
}

const remoteChatTitles = new Map<string, string>();
const recentlyBusySessions = new Set<string>();

function inferRemoteHome(folderPaths: string[]): string | null {
  for (const p of folderPaths) {
    const match = p.match(/^(\/(?:Users|home)\/[^/]+)/);
    if (match) return match[1];
    if (p.startsWith("/root/") || p === "/root") return "/root";
  }
  return null;
}

async function scanRemoteSessions(
  authority: string,
  folderPaths: string[]
): Promise<RemoteClaudeSession[]> {
  const home = inferRemoteHome(folderPaths);
  if (!home) return [];

  const sessionsDir = vscode.Uri.from({
    scheme: "vscode-remote",
    authority,
    path: `${home}/.claude/sessions`,
  });

  let entries: [string, vscode.FileType][];
  try {
    entries = await vscode.workspace.fs.readDirectory(sessionsDir);
  } catch {
    return [];
  }

  const activePids = new Set<string>();
  const sessions: RemoteClaudeSession[] = [];

  for (const [name, type] of entries) {
    if (type !== vscode.FileType.File || !name.endsWith(".json")) continue;

    const pid = name.slice(0, -5);
    activePids.add(pid);
    const fileUri = vscode.Uri.joinPath(sessionsDir, name);

    try {
      const raw = await vscode.workspace.fs.readFile(fileUri);
      const json = JSON.parse(Buffer.from(raw).toString("utf-8"));

      const sessionId: string | null = json.sessionId ?? null;
      const entrypoint: string | null = json.entrypoint ?? null;
      let status: string | null = json.status ?? null;
      const cwd: string | null = json.cwd ?? null;
      const source = entrypoint === "claude-vscode" ? "VS Code" : "Terminal";
      const titleKey = sessionId ? `${authority}:${sessionId}` : null;
      let chatTitle: string | null = titleKey ? remoteChatTitles.get(titleKey) ?? null : null;

      if (sessionId && cwd) {
        const projectKey = cwd.replace(/\//g, "-");
        const jsonlUri = vscode.Uri.from({
          scheme: "vscode-remote",
          authority,
          path: `${home}/.claude/projects/${projectKey}/${sessionId}.jsonl`,
        });

        try {
          const jsonlStat = await vscode.workspace.fs.stat(jsonlUri);

          if (Date.now() - jsonlStat.mtime < 10_000) {
            status = "busy";
            recentlyBusySessions.add(pid);
          } else if (recentlyBusySessions.has(pid)) {
            recentlyBusySessions.delete(pid);
            if (jsonlStat.size < 512 * 1024) {
              const jsonlRaw = await vscode.workspace.fs.readFile(jsonlUri);
              const jsonlText = Buffer.from(jsonlRaw).toString("utf-8");
              status = inferStatusFromContent(jsonlText);
              if (!chatTitle && titleKey) {
                chatTitle = extractTitleFromContent(jsonlText, titleKey);
              }
            }
          } else if (!chatTitle && titleKey && jsonlStat.size < 512 * 1024) {
            const jsonlRaw = await vscode.workspace.fs.readFile(jsonlUri);
            const jsonlText = Buffer.from(jsonlRaw).toString("utf-8");
            chatTitle = extractTitleFromContent(jsonlText, titleKey);
          }
        } catch {
          // JSONL doesn't exist yet
        }
      }

      sessions.push({ pid, cwd: cwd ?? "", status, sessionId, source, chatTitle });
    } catch {
      continue;
    }
  }

  for (const pid of recentlyBusySessions) {
    if (!activePids.has(pid)) recentlyBusySessions.delete(pid);
  }

  return sessions;
}

function inferStatusFromContent(text: string): string | null {
  const lines = text.trimEnd().split("\n");
  for (let i = lines.length - 1; i >= Math.max(0, lines.length - 10); i--) {
    if (!lines[i]) continue;
    try {
      const obj = JSON.parse(lines[i]);
      if (obj.type === "assistant") {
        const content = obj.message?.content;
        if (
          Array.isArray(content) &&
          content.some((b: any) => b.type === "tool_use")
        ) {
          return "permission";
        }
        return "complete";
      }
      if (obj.type === "user") return null;
    } catch {
      continue;
    }
  }
  return null;
}

function extractTitleFromContent(text: string, cacheKey: string): string | null {
  const first32k = text.slice(0, 32768);
  for (const line of first32k.split("\n")) {
    if (!line) continue;
    try {
      const obj = JSON.parse(line);
      if (obj.type !== "user") continue;
      const content = obj.message?.content;
      let userText: string | undefined;
      if (typeof content === "string") {
        userText = content;
      } else if (Array.isArray(content)) {
        userText = content.find((b: any) => b.type === "text")?.text;
      }
      if (!userText || userText.startsWith("<") || userText.length <= 5)
        continue;
      const title = (userText.trim().split("\n")[0] ?? "").slice(0, 60);
      remoteChatTitles.set(cacheKey, title);
      return title;
    } catch {
      continue;
    }
  }
  return null;
}

function post(
  path: string,
  body: object,
  onSuccess?: () => void
): Promise<void> {
  return new Promise((resolve) => {
    const data = JSON.stringify(body);
    const url = new URL(path, BASE);

    const req = http.request(
      {
        hostname: url.hostname,
        port: url.port,
        path: url.pathname,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(data),
        },
        timeout: 2000,
      },
      (res) => {
        res.resume();
        if (res.statusCode === 200) {
          onSuccess?.();
        } else {
          log(`${path} returned ${res.statusCode}`);
          registered = false;
        }
        resolve();
      }
    );

    req.on("error", (err) => {
      if ((err as NodeJS.ErrnoException).code !== "ECONNREFUSED") {
        log(`${path} error: ${err.message}`);
      }
      registered = false;
      resolve();
    });

    req.on("timeout", () => {
      req.destroy();
      registered = false;
      resolve();
    });

    req.write(data);
    req.end();
  });
}

async function register(focused?: boolean): Promise<void> {
  const payload = buildPayload();
  if (focused) {
    payload.focused = true;
  }

  if (payload.remoteAuthority) {
    try {
      payload.remoteSessions = await scanRemoteSessions(
        payload.remoteAuthority,
        payload.folderPaths
      );
    } catch (e) {
      log(`Remote scan failed: ${e}`);
    }
  }

  await post("/workspace/register", payload, () => {
    registered = true;
    log(`Registered: ${getWindowId()}`);
  });
}

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  outputChannel = vscode.window.createOutputChannel("CodeSquad");
  context.subscriptions.push(outputChannel);

  try {
    await startCommandServer();
    context.subscriptions.push({ dispose: () => { commandServer?.close(); commandServer = undefined; commandPort = undefined; } });
  } catch (err) {
    log(`Command server failed to start: ${err}`);
  }

  register();

  heartbeat = setInterval(() => register(), 10_000);

  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders(() => register()),

    vscode.extensions.onDidChange(() => register()),

    vscode.window.onDidChangeWindowState((e) => {
      if (e.focused) {
        register(true);
      }
    }),

    { dispose: () => { if (heartbeat) clearInterval(heartbeat); } }
  );
}

export async function deactivate(): Promise<void> {
  log(`Deregistering: ${getWindowId()}`);
  if (commandServer) {
    commandServer.close();
    commandServer = undefined;
    commandPort = undefined;
  }
  await post("/workspace/deregister", { windowId: getWindowId() });
}
