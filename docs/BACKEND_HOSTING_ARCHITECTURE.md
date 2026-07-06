# Buildify — Production Architecture & Backend Hosting Specification

**Document Version:** 1.0.0  
**Last Updated:** July 6, 2026  
**Status:** Approved Technical Specification  

---

## 1. Executive Summary & Philosophy

Buildify is an edge-cloud orchestration platform that enables developers to host AI models (LLMs via `llama.cpp`) and custom backend services (Node.js, Python FastAPI, Flask, etc. cloned from Git) directly on mobile devices (Android/iOS). These services are exposed securely to the public internet via **Cloudflare Tunnels** (`username.buildify.me`) and private mesh networks via **Tailscale**.

To achieve a true **Production-Level Environment** on mobile hardware, Buildify must balance two competing realities:
1. **Always-On Reliability:** Production APIs and AI agents need to survive app restarts, OS backgrounding, and device reboots without losing state or configuration.
2. **Resource & Storage Constraints:** Mobile devices have limited disk space (128GB–256GB). Unchecked cloning of Git repositories, `node_modules`, and Python virtual environments (`venv`) will rapidly consume device storage and degrade phone performance.

This document outlines the production-grade architecture designed to solve these challenges through **Dual-Mode Hosting (Persistent vs. Ephemeral)** and **Relational SQLite Persistence**.

---

## 2. The Storage Problem & Architectural Discussion

### The Discussion
When a user clones a backend repository from GitHub onto their phone, it pulls down dependencies (`package.json`, `requirements.txt`). In traditional desktop or cloud environments (like AWS or Vercel), disk space is abundant or disposable. On a user's primary mobile phone, if a developer clones 5–10 repos just to test a pull request or demo a temporary webhook, those projects can easily waste **5–10 GB of storage**.

### The Dual-Mode Solution
Inspired by Docker (`docker run --rm`) and ephemeral cloud workspaces (GitHub Codespaces / Replit), Buildify implements two distinct hosting tiers for any deployed service:

```
                  ┌─────────────────────────────────┐
                  │   User Creates New Service      │
                  │   (Git Clone / Model Run)       │
                  └───────────────┬─────────────────┘
                                  │
                  ┌───────────────▼─────────────────┐
                  │    Select Hosting Mode Tier     │
                  └───────┬─────────────────┬───────┘
                          │                 │
            📌 PERSISTENT │                 │ ⚡ EPHEMERAL
                          │                 │
          ┌───────────────▼──────┐   ┌──────▼────────────────┐
          │ Permanent Storage    │   │ OS Cache Directory    │
          │ (/files/projects/)   │   │ (/cache/ephemeral/)   │
          ├──────────────────────┤   ├───────────────────────┤
          │ SQLite Logged        │   │ In-Memory / TTL Tag   │
          ├──────────────────────┤   ├───────────────────────┤
          │ Auto-Restarts on Boot│   │ Auto-Wiped on Stop    │
          └──────────────────────┘   └──────────────────────┘
```

#### 1. ⚡ Ephemeral / Sandbox Mode ("Test & Discard")
* **Use Case:** One-time testing, reviewing a colleague's PR, hosting a temporary webhook for a hackathon, or quick API experimentation.
* **Storage Location:** Cloned directly into the OS temporary/cache directory:  
  `data/user/0/com.example.buildify_flutter/cache/ephemeral/<session_id>/`
* **UI Representation:** Displayed on the Home Page dashboard with a distinct **`⚡ EPHEMERAL`** or **`🧪 SANDBOX`** badge.
* **Garbage Collection (Auto-Cleanup):**
  * **Immediate Wiping:** Tapping **"Stop Server"** or **"Destroy"** instantly deletes the cloned folder, wipes all dependencies (`node_modules`), and removes the project from memory.
  * **OS Cache Reclamation:** Because files reside in the system cache directory, iOS and Android OS will automatically purge these files if the device ever runs low on storage.
  * **TTL Expiration:** Users can set an optional timer (e.g., "Expire in 2 hours"), after which a background worker terminates the process and purges the directory.

#### 2. 📌 Persistent Mode ("Production / Always-On")
* **Use Case:** Personal production APIs, home automation backends, custom AI agents, or long-term web services.
* **Storage Location:** Cloned into permanent app document storage:  
  `data/user/0/com.example.buildify_flutter/files/projects/<project_id>/`
* **UI Representation:** Displayed as a permanent project card with live status indicators (glowing green `ONLINE` or offline grey).
* **Persistence:** Logged in the relational SQLite database. Remembers environment variables, custom subdomain routings, and auto-restarts automatically upon phone reboot.
* **Promotion:** Users can convert an Ephemeral session into a Persistent project at any time by tapping **"Pin / Save to Projects"**.

---

## 3. Data Persistence Layer (SQLite & Secure Storage)

To manage multiple custom backends and AI servers reliably, Buildify uses a hybrid persistence layer:
1. **SQLite (`sqflite` / `drift`):** For structured relational data, project lists, and deployment histories.
2. **Flutter Secure Storage (`flutter_secure_storage`):** For encrypted API keys, tokens, and SSH Git credentials.

### SQLite Database Schema (`buildify.db`)

#### Table: `projects`
Stores the registry of all user-created services (both AI models and cloned Git backends).

| Column | SQL Type | Description |
| :--- | :--- | :--- |
| `id` | `TEXT PRIMARY KEY` | Unique UUID (e.g., `srv_8f92a10b...`) |
| `name` | `TEXT NOT NULL` | Display name (e.g., `paperstudio-api`, `llama-3-8b`) |
| `type` | `TEXT NOT NULL` | Runtime enum: `ai_model`, `nodejs`, `python`, `static` |
| `hosting_mode` | `TEXT NOT NULL` | Tier: `persistent` or `ephemeral` |
| `source_uri` | `TEXT NOT NULL` | Git repository URL or local GGUF file path |
| `local_path` | `TEXT NOT NULL` | Absolute path on mobile filesystem |
| `port` | `INTEGER NOT NULL` | Allocated localhost port (e.g., `3000`, `8080`) |
| `subdomain` | `TEXT` | Cloudflare tunnel routing (e.g., `myapi.buildify.me`) |
| `env_vars` | `TEXT` | JSON-encoded map of non-secret environment variables |
| `desired_state` | `TEXT NOT NULL` | Expected lifecycle state: `running` or `stopped` |
| `created_at` | `INTEGER NOT NULL` | Unix timestamp of project creation |
| `last_active_at`| `INTEGER NOT NULL` | Unix timestamp of last successful ping/request |

#### Table: `deployments`
Tracks execution logs, build histories, and crash reports for each project.

| Column | SQL Type | Description |
| :--- | :--- | :--- |
| `id` | `TEXT PRIMARY KEY` | Deployment UUID |
| `project_id` | `TEXT NOT NULL` | Foreign key referencing `projects(id)` |
| `commit_hash` | `TEXT` | Git SHA if cloned from repository |
| `status` | `TEXT NOT NULL` | Status: `building`, `success`, `failed`, `crashed` |
| `log_file_path` | `TEXT` | Path to persistent terminal log file on disk |
| `started_at` | `INTEGER NOT NULL` | Unix timestamp of build start |

---

## 4. App Hydration & Process Lifecycle

In a mobile operating system, background processes can be suspended or killed by the OS (Battery Saver / Low Memory Killer). When the Buildify app is opened or restarted, it executes the **Hydration & Reconciliation Loop**:

```
[App Boot] ──> [1. Query SQLite Projects] ──> [2. Ping Native Run-Time Ports]
                                                      │
                       ┌──────────────────────────────┴──────────────────────────────┐
                       ▼                                                             ▼
           [Port Alive / Process OK]                                     [Port Dead / Process Killed]
                       │                                                             │
                       ▼                                                             ▼
         • Update UI to ONLINE (Green)                                  • Check `desired_state` in DB
         • Re-attach Log Streamers                                      • If 'running': Trigger Auto-Restart
                                                                        • If 'stopped': Show OFFLINE (Grey)
```

1. **Database Read:** Load all records from `projects` where `hosting_mode = 'persistent'` (and any active ephemeral sessions).
2. **Native Health Check:** For each project, invoke `NativeServerBridge.checkPortStatus(port)`.
3. **Reconciliation:**
   * If `desired_state == 'running'` but the port is dead (e.g., OS killed the process overnight), Buildify automatically invokes the native runtime to **re-launch the server and re-establish the Cloudflare Tunnel**.
   * If `desired_state == 'stopped'`, mark as `OFFLINE` and wait for manual user start.

---

## 5. Implementation Roadmap

### Phase 1: Core AI Server Persistence (Current Milestone)
* **Goal:** Eliminate the immediate bug where `selectedModelId` resets to default upon app Hot Restart or reboot.
* **Action:** Bind `selectedModelId` and `serverStatus` to `flutter_secure_storage` inside `AiServerController`.
* **Outcome:** When the user selects a model and starts the AI server, Buildify remembers the exact model configuration across sessions.

### Phase 2: Relational SQLite & Dual-Mode Git Hosting (Next Milestone)
* **Goal:** Enable full custom backend hosting (Node.js/Python) with Ephemeral/Persistent tier selection.
* **Action:**
  1. Add `sqflite` and `path_provider` to `pubspec.yaml`.
  2. Implement `DatabaseHelper` and initialize `buildify.db` with the `projects` table schema.
  3. Refactor `ProjectsHomePage` to replace hardcoded lists (`flash_news_ai`, `paperstudio`) with a live reactive query of `projects` from SQLite.
  4. Build the **"Ephemeral vs. Persistent"** toggle into the service creation modal, wiring up automatic garbage collection for `/cache/ephemeral/`.
