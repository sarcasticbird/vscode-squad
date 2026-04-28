"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = __importStar(require("vscode"));
const http = __importStar(require("http"));
const PORT = 9876;
const BASE = `http://127.0.0.1:${PORT}`;
let registered = false;
function getWindowId() {
    return `${process.pid}`;
}
function buildPayload() {
    const folders = (vscode.workspace.workspaceFolders ?? []).map((f) => f.uri.fsPath);
    const claudeExt = vscode.extensions.getExtension("anthropic.claude-code");
    return {
        windowId: getWindowId(),
        workspaceName: vscode.workspace.name ?? folders[0]?.split("/").pop() ?? "Unknown",
        folderPaths: folders,
        claudeInstalled: claudeExt !== undefined,
        claudeActive: claudeExt?.isActive ?? false,
    };
}
function post(path, body, onSuccess) {
    const data = JSON.stringify(body);
    const url = new URL(path, BASE);
    const req = http.request({
        hostname: url.hostname,
        port: url.port,
        path: url.pathname,
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "Content-Length": Buffer.byteLength(data),
        },
        timeout: 2000,
    }, (res) => {
        if (res.statusCode === 200) {
            onSuccess?.();
        }
    });
    req.on("error", () => { });
    req.write(data);
    req.end();
}
function register() {
    post("/workspace/register", buildPayload(), () => {
        registered = true;
    });
}
function deregister() {
    post("/workspace/deregister", { windowId: getWindowId() });
}
function activate(context) {
    register();
    context.subscriptions.push(vscode.workspace.onDidChangeWorkspaceFolders(() => register()), vscode.window.onDidChangeWindowState((e) => {
        if (e.focused) {
            if (!registered) {
                register();
            }
            post("/workspace/focus", { windowId: getWindowId() });
        }
    }));
}
function deactivate() {
    deregister();
}
