import * as vscode from "vscode";
import * as http from "http";

const PORT = 9876;
const BASE = `http://127.0.0.1:${PORT}`;

interface WorkspacePayload {
  windowId: string;
  workspaceName: string;
  folderPaths: string[];
  claudeInstalled: boolean;
  claudeActive: boolean;
}

let registered = false;
let outputChannel: vscode.OutputChannel;

function getWindowId(): string {
  return vscode.env.sessionId;
}

function log(msg: string): void {
  outputChannel?.appendLine(`[${new Date().toISOString()}] ${msg}`);
}

function buildPayload(): WorkspacePayload {
  const folders = (vscode.workspace.workspaceFolders ?? []).map(
    (f) => f.uri.fsPath
  );
  const claudeExt = vscode.extensions.getExtension("anthropic.claude-code");

  return {
    windowId: getWindowId(),
    workspaceName:
      vscode.workspace.name ?? folders[0]?.split("/").pop() ?? "Unknown",
    folderPaths: folders,
    claudeInstalled: claudeExt !== undefined,
    claudeActive: claudeExt?.isActive ?? false,
  };
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

async function register(): Promise<void> {
  await post("/workspace/register", buildPayload(), () => {
    registered = true;
    log(`Registered: ${getWindowId()}`);
  });
}

export function activate(context: vscode.ExtensionContext): void {
  outputChannel = vscode.window.createOutputChannel("CodeSquad");
  context.subscriptions.push(outputChannel);

  register();

  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders(() => register()),

    vscode.window.onDidChangeWindowState((e) => {
      if (e.focused) {
        if (!registered) {
          register().then(() => {
            if (registered) {
              post("/workspace/focus", { windowId: getWindowId() });
            }
          });
        } else {
          post("/workspace/focus", { windowId: getWindowId() });
        }
      }
    })
  );
}

export function deactivate(): Promise<void> {
  log(`Deregistering: ${getWindowId()}`);
  return post("/workspace/deregister", { windowId: getWindowId() });
}
