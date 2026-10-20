# Antigravity Agent Cockpit

<p align="center">
  <strong>The Real-Time Mission Control, Flight Recorder & Cybersecurity Audit Suite for Google Antigravity Autonomous Coding Agents.</strong>
</p>

<p align="center">
  <a href="#platform-support"><img src="https://img.shields.io/badge/Platform-macOS%20(Primary)-blue.svg?style=for-the-badge" alt="Platform"></a>
  <a href="#key-features"><img src="https://img.shields.io/badge/Status-Production%20Ready%20(macOS)-brightgreen.svg?style=for-the-badge" alt="Status"></a>
  <a href="#architecture"><img src="https://img.shields.io/badge/Engine-LuaJIT%202.1%20%2B%20Svelte%204-orange.svg?style=for-the-badge" alt="Engine"></a>
  <a href="#architecture"><img src="https://img.shields.io/badge/Runtime-Tauri--Lua%20(Native%20Webview)-blue.svg?style=for-the-badge" alt="Runtime"></a>
  <a href="#ultra-lightweight-footprint"><img src="https://img.shields.io/badge/App%20Size-~2.4%20MB-success.svg?style=for-the-badge" alt="Size"></a>
  <a href="#license"><img src="https://img.shields.io/badge/License-MIT-purple.svg?style=for-the-badge" alt="License"></a>
</p>

---

## Overview

When autonomous AI coding agents execute terminal commands, modify source files, install dependencies, and query remote APIs on your development machine, **blind trust is not an option**.

**Antigravity Agent Cockpit** is a native, ultra-lightweight desktop control center purpose-built for **Google Antigravity**. It connects directly to the agent's runtime trajectory, providing **sub-millisecond flight telemetry**, **deep reasoning introspection**, and a **proactive cybersecurity rules engine** that audits every single agent action in real time.

Built on the blazing-fast **Tauri-Lua** architecture (native system webview + LuaJIT 2.1), Cockpit launches in **< 150ms** and consumes **< 40MB RAM**—offering a native desktop experience without the overhead of heavy Electron apps.

---

## Platform Support

* **macOS (Apple Silicon & Intel)**: **Fully Supported & Tested (Tier 1)**. Native WKWebView, Cocoa bundle integration, and codesigning.
* **Linux**: **Experimental / In Progress**. Supported by the Tauri-Lua WebKitGTK runtime; shell hooks and directory discovery are being normalized.
* **Windows**: **Planned Roadmap**. Dependent on WebView2 bindings and POSIX syscall abstractions.

---

## Ultra-Lightweight Footprint

The complete standalone macOS application weighs only **~2.4 MB** (with a **2.2 MB** DMG installer).

This featherweight size and instant startup are made possible thanks to **Tauri-Lua** and **Svelte**, delivering a full-featured desktop control center without the hundreds of megabytes typical of other desktop apps.

---

## Key Features

### Real-Time Flight Recorder & Trajectory Streaming
* **Live Step-by-Step Telemetry**: Watch the agent think, plan, inspect files, and execute shell commands live as they occur.
* **Exact Turn Timing & Durations**: Displays precise start time, completion timestamp, and execution duration (e.g., `58s`, `4m 12s`, or live active counter) for every conversation turn.
* **Multi-Density Execution Canvas**:
  * **Compact Mode**: Ultra-dense, single-line terminal view with accordion expanders—perfect for scanning through 50+ rapid-fire operations.
  * **Detailed Mode**: Full syntax-highlighted command boxes, formatted diff views, and one-click clipboard copying.
* **Smart Step Filtering**: Instant 0ms filtering by category: *Terminal Commands*, *File Mutations*, *Code Inspections*, *Security Alerts*, and *Internal Thoughts*.

### Real-Time Cybersecurity & Prompt Injection Engine
Autonomous agents are vulnerable to indirect prompt injection from malicious files, web pages, or dependency scripts. Cockpit inspects every single tool invocation and agent payload:
* **Prompt Injection & Directive Hijack Defense**: Detects instruction override attempts (`ignore previous instructions`, `system override`, role spoofing, jailbreak signatures).
* **Workspace Boundary Escape Protection**: Flags unauthorized directory traversals (`../..`), absolute path escapes, and operations outside the approved project workspace.
* **Hardcoded Secret & API Key Scanner**: Scans inputs and command arguments for exposed AWS keys, GitHub PATs, private keys, and OpenAI tokens.
* **Egress & Package Installation Radar**: Tracks outbound network calls (`curl`, `wget`, reverse shells) and package manager invocations (`npm install`, `pip`, `cargo`).
* **Automated Forensic Audit Reports**: One-click export of comprehensive compliance and security audit reports in Markdown and JSON format.

### Instant Multi-Session Switcher
* Seamlessly monitor multiple agent conversations and background tasks across different projects.
* Switch between active and historical sessions with **zero app reload** and automatic cache hydration.

---

## Architecture

Antigravity Agent Cockpit decouples heavyweight telemetry parsing from UI rendering using a local IPC bridge:

```
┌────────────────────────────────────────────────────────┐
│               Antigravity IDE / CLI                    │
│      (~/.gemini/antigravity-ide/brain/<uuid>/)         │
└──────────────────────────┬─────────────────────────────┘
                           │ (Telemetry, SQLite DB, Logs)
                           ▼
┌────────────────────────────────────────────────────────┐
│             Tauri-Lua Native Backend                   │
│  • Flight Recorder (flight_recorder.lua)               │
│  • Cybersecurity Rules Engine & Secret Scanner         │
│  • Sub-millisecond JSON Parser & Path Resolver         │
└──────────────────────────┬─────────────────────────────┘
                           │ (Asynchronous IPC Channels)
                           ▼
┌────────────────────────────────────────────────────────┐
│              Svelte 4 Reactive Frontend                │
│  • Turn Canvas & Timeline Stepper                      │
│  • Real-Time Security Radar & Audit Dashboard          │
│  • Dual-Density Step Inspector (Compact / Detailed)    │
└────────────────────────────────────────────────────────┘
```

---

## Getting Started

### Prerequisites
* **Operating System**: macOS 12+ (Apple Silicon or Intel).
* **Node.js**: v18+ & `npm`.
* **LuaJIT**: Installed via Homebrew (`brew install luajit`) or bundled runtime.

### Installation & Development

1. **Clone the repository**:
   ```bash
   git clone https://github.com/MoxPy/antigravity-agent-cockpit.git
   cd antigravity-agent-cockpit
   ```

2. **Install frontend dependencies**:
   ```bash
   npm install
   ```

3. **Launch Cockpit in Live Development Mode**:
   ```bash
   ./lua-tauri dev
   ```
   *Vite Hot-Module Replacement (HMR) and backend Lua hot-reloading will automatically initialize.*

4. **Build Production Binary**:
   ```bash
   ./lua-tauri build
   ```
   The optimized standalone application bundle will be output to `./build/Antigravity Agent Cockpit.app`.

---

## Security Best Practices

> **Note**: Antigravity Agent Cockpit operates entirely **locally on your machine**. It does not phone home, transmit telemetry to external servers, or store credentials in the cloud. All audit logs, trajectory files, and session states remain securely inside your local sandbox.

---

## Contributing

Contributions, feature suggestions, and security rule improvements are warmly welcomed!
1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## License

Distributed under the **MIT License**. See [`LICENSE`](./LICENSE) for more details.

<p align="center">
  Built for the Google Antigravity developer community.
</p>
