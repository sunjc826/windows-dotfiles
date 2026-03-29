---
name: vscode-extension
description: Use when creating, scaffolding, or modifying VSCode extensions. Covers project structure, cross-platform compatibility (Windows/macOS/Linux), WebView integration, bundling, testing, and publishing.
user-invocable: false
---

# VSCode Extension Development

## Overview

Guide for building production-quality VSCode extensions that work flawlessly on **Windows, macOS, and Linux**. Cross-platform correctness is a first-class concern at every stage.

## Project Structure

```
extension-name/
  .vscode/
    launch.json          # Extension Host debug config
    tasks.json           # Build tasks
  src/
    extension.ts         # Entry point: activate() / deactivate()
    commands/            # Command handlers
    providers/           # TreeView, WebView, language providers
    webview/             # WebView UI source (if applicable)
      index.html
      main.ts
      styles.css
  test/
    suite/               # Integration tests
    unit/                # Unit tests
  media/                 # Icons, images
  dist/                  # Bundled output (gitignored)
  package.json
  tsconfig.json
  esbuild.config.mjs    # Or webpack.config.js
  .vscodeignore
  CHANGELOG.md
  README.md
  LICENSE
```

## package.json Essentials

```jsonc
{
  "name": "extension-name",
  "displayName": "Extension Name",
  "publisher": "publisher-id",
  "version": "0.1.0",
  "engines": { "vscode": "^1.85.0" },
  "categories": ["Other"],
  "main": "./dist/extension.js",
  "activationEvents": [],  // prefer contributes-based implicit activation
  "contributes": {
    "commands": [],
    "views": {},
    "viewsContainers": {},
    "configuration": {},
    "menus": {}
  },
  "scripts": {
    "vscode:prepublish": "npm run build",
    "build": "node esbuild.config.mjs --production",
    "watch": "node esbuild.config.mjs --watch",
    "test": "vscode-test",
    "lint": "eslint src",
    "package": "vsce package"
  },
  "devDependencies": {
    "@types/vscode": "^1.85.0",
    "@types/node": "^20.0.0",
    "@vscode/test-cli": "^0.0.10",
    "@vscode/test-electron": "^2.4.0",
    "@vscode/vsce": "^3.0.0",
    "esbuild": "^0.24.0",
    "typescript": "^5.5.0"
  }
}
```

### Activation Events

- **Prefer implicit activation** via `contributes` (commands, views, languages) — VSCode infers activation events automatically.
- **Never use `"*"`** — it degrades startup performance.
- Use `onStartupFinished` only for truly background work.
- Use `workspaceContains:**/pattern` for project-type detection.

## Cross-Platform Rules (MANDATORY)

Every extension MUST follow these rules. Violations cause silent failures on other platforms.

### File Paths

```typescript
// ALWAYS use the VSCode URI / path APIs
import * as vscode from 'vscode';
import * as path from 'path';

// Good: platform-agnostic
const filePath = path.join(workspaceFolder, 'config', 'settings.json');
const uri = vscode.Uri.joinPath(workspaceUri, 'config', 'settings.json');

// BAD: hardcoded separators
const bad = workspaceFolder + '\\config\\settings.json';
```

**Rules:**
- Use `path.join()`, `path.resolve()`, `path.sep` — never concatenate with `/` or `\`.
- Use `vscode.Uri.joinPath()` for URI-based paths.
- Never assume drive letters (`C:\`).
- Never assume case sensitivity — macOS HFS+ and Windows NTFS are case-insensitive.
- Use `vscode.workspace.fs` instead of `fs` module for virtual filesystem support (Remote SSH, WSL, Containers).

### Shell / Process Execution

```typescript
import * as cp from 'child_process';

// Good: let Node pick the shell, or be explicit
cp.execFile('node', ['script.js'], { cwd: workspaceDir });

// If you must use shell: specify it per-platform
const shell = process.platform === 'win32' ? 'cmd.exe' : '/bin/sh';
const shellFlag = process.platform === 'win32' ? '/c' : '-c';
cp.exec(command, { shell });

// Or avoid shell entirely — prefer spawn/execFile with argument arrays
cp.spawn('git', ['status', '--porcelain'], { cwd: workspaceDir });
```

**Rules:**
- Prefer `spawn` / `execFile` with argument arrays over `exec` with shell strings.
- If shell is needed, set it explicitly or use `vscode.ShellExecution` which handles platform differences.
- Never assume `bash`, `/bin/sh`, or `cmd.exe` exists — detect via `process.platform`.
- Environment variables: access via `process.env` (Node normalizes `PATH` vs `Path`).

### Line Endings

- Use `vscode.EndOfLine` enum when reading/writing editor content.
- For files, use `\n` internally and let git / `.gitattributes` handle conversion.
- Ship `.gitattributes` with `* text=auto` in extension repos.

### Temporary Files

```typescript
import * as os from 'os';
import * as path from 'path';

const tmpDir = os.tmpdir(); // Cross-platform temp directory
const tmpFile = path.join(tmpDir, `ext-${Date.now()}.tmp`);
```

- Never hardcode `/tmp` or `%TEMP%`.

### Keyboard Shortcuts

- Use `Cmd` on macOS, `Ctrl` on Windows/Linux: VSCode handles this via `"key": "ctrl+shift+p"` which auto-maps `Cmd` on macOS.
- Use the `when` clause `isMac` / `isWindows` / `isLinux` only when platform-specific behavior differs.

## WebView Development

### Security

```typescript
const panel = vscode.window.createWebviewPanel(
  'viewType', 'Title',
  vscode.ViewColumn.One,
  {
    enableScripts: true,
    localResourceRoots: [
      vscode.Uri.joinPath(context.extensionUri, 'media'),
      vscode.Uri.joinPath(context.extensionUri, 'dist', 'webview')
    ],
    // retainContextWhenHidden: true  // only if state preservation is critical
  }
);
```

- Set `localResourceRoots` to the minimum required directories.
- Always include a Content Security Policy in the HTML.
- Use `webview.cspSource` for the CSP nonce source.

### Resource Loading

```typescript
// Convert local file to webview-safe URI
const scriptUri = panel.webview.asWebviewUri(
  vscode.Uri.joinPath(context.extensionUri, 'dist', 'webview', 'main.js')
);
const styleUri = panel.webview.asWebviewUri(
  vscode.Uri.joinPath(context.extensionUri, 'media', 'styles.css')
);
```

- **Never** use `file://` URIs directly.
- **Always** use `webview.asWebviewUri()`.

### HTML Template with CSP

```typescript
function getWebviewContent(webview: vscode.Webview, extensionUri: vscode.Uri): string {
  const nonce = getNonce();
  const scriptUri = webview.asWebviewUri(
    vscode.Uri.joinPath(extensionUri, 'dist', 'webview', 'main.js')
  );
  const styleUri = webview.asWebviewUri(
    vscode.Uri.joinPath(extensionUri, 'media', 'styles.css')
  );
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="
    default-src 'none';
    style-src ${webview.cspSource} 'nonce-${nonce}';
    script-src 'nonce-${nonce}';
    img-src ${webview.cspSource} https:;
    font-src ${webview.cspSource};
  ">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link href="${styleUri}" rel="stylesheet">
</head>
<body>
  <div id="root"></div>
  <script nonce="${nonce}" src="${scriptUri}"></script>
</body>
</html>`;
}

function getNonce(): string {
  const array = new Uint32Array(4);
  require('crypto').getRandomValues(array);
  return array.join('-');
}
```

### Extension <-> WebView Communication

```typescript
// Extension -> WebView
panel.webview.postMessage({ type: 'update', data: payload });

// WebView -> Extension (inside webview script)
const vscode = acquireVsCodeApi();
vscode.postMessage({ type: 'action', data: payload });

// Extension listens
panel.webview.onDidReceiveMessage(message => {
  switch (message.type) {
    case 'action': handleAction(message.data); break;
  }
});
```

### Theming

```css
/* Use VSCode CSS variables for automatic theme support */
body {
  color: var(--vscode-foreground);
  background-color: var(--vscode-editor-background);
  font-family: var(--vscode-font-family);
  font-size: var(--vscode-font-size);
}

button {
  background: var(--vscode-button-background);
  color: var(--vscode-button-foreground);
  border: none;
  padding: 6px 14px;
  cursor: pointer;
}
button:hover {
  background: var(--vscode-button-hoverBackground);
}
```

- Use `var(--vscode-*)` tokens for all colors, fonts, and spacing.
- Test with both light and dark themes.
- For UI-heavy WebViews: **REQUIRED SKILL:** Use `frontend-design:frontend-design` for distinctive, polished UI that goes beyond generic component styling.

### WebView UI Toolkit

For standard VSCode-style components, use `@vscode/webview-ui-toolkit`:

```bash
npm install @vscode/webview-ui-toolkit
```

This provides pre-built, theme-aware components (buttons, text fields, dropdowns, data grids, etc.) that match the native VSCode look.

## Bundling

Use **esbuild** (preferred for speed) or webpack.

```javascript
// esbuild.config.mjs
import * as esbuild from 'esbuild';

const production = process.argv.includes('--production');
const watch = process.argv.includes('--watch');

/** @type {import('esbuild').BuildOptions} */
const extensionConfig = {
  entryPoints: ['src/extension.ts'],
  bundle: true,
  outfile: 'dist/extension.js',
  external: ['vscode'],
  format: 'cjs',
  platform: 'node',
  sourcemap: !production,
  minify: production,
};

// Separate build for WebView code (browser target)
const webviewConfig = {
  entryPoints: ['src/webview/main.ts'],
  bundle: true,
  outfile: 'dist/webview/main.js',
  format: 'iife',
  platform: 'browser',
  sourcemap: !production,
  minify: production,
};

if (watch) {
  const ctx1 = await esbuild.context(extensionConfig);
  const ctx2 = await esbuild.context(webviewConfig);
  await Promise.all([ctx1.watch(), ctx2.watch()]);
} else {
  await esbuild.build(extensionConfig);
  await esbuild.build(webviewConfig);
}
```

**Key rules:**
- `vscode` module is **always** external — it's provided by the runtime.
- Extension code: `platform: 'node'`, `format: 'cjs'`.
- WebView code: `platform: 'browser'`, `format: 'iife'` or `'esm'`.

## .vscodeignore

```
.vscode/**
src/**
test/**
node_modules/**
.gitignore
tsconfig.json
esbuild.config.mjs
**/*.map
```

Only ship `dist/`, `media/`, `package.json`, `README.md`, `CHANGELOG.md`, `LICENSE`.

## Testing

### Setup

```jsonc
// .vscode-test.mjs
import { defineConfig } from '@vscode/test-cli';

export default defineConfig({
  files: 'out/test/**/*.test.js',
  mocha: { timeout: 20000 },
});
```

### Integration Test Example

```typescript
import * as assert from 'assert';
import * as vscode from 'vscode';

suite('Extension Test Suite', () => {
  test('Extension should activate', async () => {
    const ext = vscode.extensions.getExtension('publisher.extension-name');
    assert.ok(ext);
    await ext!.activate();
    assert.strictEqual(ext!.isActive, true);
  });
});
```

### Cross-Platform Testing

- Test on all three platforms via CI (GitHub Actions matrix):

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
```

- Use `@vscode/test-electron` which handles headless display setup.
- On Linux CI, set `xvfb-run` or use the built-in display server support.

## Publishing

```bash
# Package locally
npx @vscode/vsce package

# Publish (requires Personal Access Token)
npx @vscode/vsce publish

# Platform-specific builds (for native dependencies only)
npx @vscode/vsce package --target win32-x64
npx @vscode/vsce package --target darwin-arm64
npx @vscode/vsce package --target linux-x64
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Hardcoded path separators (`/` or `\`) | Use `path.join()` or `vscode.Uri.joinPath()` |
| Using `fs` for workspace files | Use `vscode.workspace.fs` (supports remote) |
| `"activationEvents": ["*"]` | Use specific events or implicit activation |
| `file://` URIs in WebView | Use `webview.asWebviewUri()` |
| Missing CSP in WebView | Always set Content-Security-Policy |
| Assuming shell availability | Detect platform, prefer `spawn` with args array |
| Not bundling | Always bundle — reduces size and activation time |
| Case-sensitive file assumptions | macOS/Windows are case-insensitive by default |
| Hardcoded `/tmp` or `%TEMP%` | Use `os.tmpdir()` |
| Using `retainContextWhenHidden` freely | Costly — only use when state preservation is essential |
