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

function getWindowId(): string {
  return `${process.pid}`;
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

function post(path: string, body: object, onSuccess?: () => void): void {
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
      if (res.statusCode === 200) {
        onSuccess?.();
      }
    }
  );

  req.on("error", () => {});
  req.write(data);
  req.end();
}

function register(): void {
  post("/workspace/register", buildPayload(), () => {
    registered = true;
  });
}

function deregister(): void {
  post("/workspace/deregister", { windowId: getWindowId() });
}

export function activate(context: vscode.ExtensionContext): void {
  register();

  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders(() => register()),

    vscode.window.onDidChangeWindowState((e) => {
      if (e.focused) {
        if (!registered) {
          register();
        }
        post("/workspace/focus", { windowId: getWindowId() });
      }
    })
  );
}

export function deactivate(): void {
  deregister();
}
