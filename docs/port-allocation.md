# Port Allocation Strategy

**Last Updated:** August 16, 2026

---

## Why Ports 3000–3099?

Buildify auto-assigns localhost ports from the range **3000–3099** for hosted backend projects. Port **8080** is reserved exclusively for AI model inference (llama.cpp server).

### Rationale

| Concern | Decision |
|---------|----------|
| **Avoid system ports** | Ports 0–1023 are "well-known" ports reserved by the OS (HTTP = 80, HTTPS = 443, SSH = 22). Android forbids non-root apps from binding to these ports. |
| **Avoid registered service ports** | Ports 1024–2999 are commonly used by system daemons and registered IANA services (e.g., MySQL = 3306, PostgreSQL = 5432). Binding to these risks collisions. |
| **Developer familiarity** | Port 3000 is the default for Node.js (Express), React dev server, Rails, and many other frameworks. Developers instinctively expect their backends on 3000+. |
| **Avoid Android internal ports** | Android Debug Bridge (ADB) uses port 5037. Chrome DevTools uses 9222. Staying in 3000–3099 avoids all of these. |
| **100-port capacity** | Supporting up to 100 concurrent hosted projects is more than sufficient for a mobile device. If a user somehow exceeds 100 services, the app surfaces an error. |
| **AI model isolation** | Port 8080 is reserved for the llama.cpp inference server (`AiServerService.kt`). Keeping backend projects on a separate range (3000+) prevents conflicts. |

### Allocation Algorithm

```
1. Query SQLite: SELECT port FROM projects ORDER BY port ASC
2. Walk through 3000, 3001, 3002, ... 3099
3. Return the first port NOT already assigned to a project
4. If all 100 ports are taken, throw PortExhaustionError
```

### Port Lifecycle

| Event | Port Behavior |
|-------|--------------|
| **Project created** | Next available port (3000–3099) is assigned and saved to SQLite |
| **Project started** | Server binds to the assigned port on `0.0.0.0` |
| **Project stopped** | Port is released (process killed), but the assignment stays in SQLite |
| **Project deleted** | Port assignment is removed from SQLite, port becomes available |
| **App restart** | Ports are re-read from SQLite; running projects re-bind to their saved port |

### Reserved Ports

| Port | Owner | Notes |
|------|-------|-------|
| `8080` | AI Model Server (llama.cpp) | Hardcoded in `AiServerService.kt` |
| `3000–3099` | Hosted backend projects | Auto-assigned by `EmbeddedBackendService` |
| `5037` | ADB (Android Debug Bridge) | System-reserved, never used by Buildify |

### User Override

Users can manually set a custom port in the project settings page. If the chosen port conflicts with an existing project or a reserved port, the UI shows a validation error and suggests the next available port.
