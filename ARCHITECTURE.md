# magentic-runtime architecture

One **Cyborg (Dev/AI) experience**, several runtime hosts (browser plugin, Docker
Desktop container, later web-online + GalaxyGate VPS). Consistency is guaranteed by
**two shared seams**, not by shared storage:

1. the **immutable governed core** (SHA-referenced), and
2. the **stateless MCP2 interface** the AI sees (added next, on top of these layers).

Host, storage substrate (SQLite vs OPFS-SQLite), LLM (local wllama/Ollama vs remote
API), and UI are all host-local and may differ. What the AI touches and what is
governed do not.

## Layers

```
Code
  Immutable   -- SHA-referenced, no history (the digest IS the version)
    Immutable::TrustLadder     fail-closed boundary: canary + edge-grant enforcement
    Immutable::Grammar         RailsRunner Grammar (rr-grammar): contract-set, compile, project
    Immutable::ReleasePacket   the signed, content-addressed release artifact
  Mutable     -- working / derived, evolves
    Mutable::Store             result.sqlite working data (bronze/silver tiers)
    Mutable::Medallion         bronze -> silver -> gold transform
    Mutable::GraphProjection   the public JSON-LD view of the gold row
    (UI)                       host-local; not in the runtime core yet
  Git         -- local code mutations
    Git::Workspace             history for the mutable artifacts (immutable needs none)

MCP2 interface (STATELESS)  -- the ONE seam the Cyborg/AI sees  [NEXT: vv-mcb Mcp2::Facade]
    discover -> invoke, never-raise envelope, MRTR multi-turn, Continuation store
    for durable-state-out-of-session
```

## Medallion = the local acts

| Tier | Act | What |
|---|---|---|
| BRONZE | `run` | model produces a raw typed row |
| SILVER | `run` | persisted to result.sqlite + typed proposal + gate RE-READS SQL (stops at validated) |
| GOLD | `approve` | human promotion: re-read persisted SQL, gate accepts, project + canary, sign the Release Packet |
| (package) | `package` | component.yaml + component_digest (deployable Magentic Component) |

Fail-closed throughout: a bad proposal, missing SQL evidence, a canary leak, or an
over-broad edge grant aborts WITHOUT emitting a projection or packet.

## Why the layers

- **Immutable** is pure and content-addressed: same input -> same SHA, so it needs no
  history and is identical on every host. This is what makes a result verifiable and
  a deployment refusable-by-evidence.
- **Mutable** is where work happens and changes; it gets its history from **Git**.
- The **MCP2** facade (next) exposes a single stateless tool over these layers so the
  offline-laptop Cyborg and the web-online Cyborg have the identical AI experience.

## WebDAV substrate (files over HTTP, no volume mounts)

The workspace is reached over **standards-based WebDAV** (an HTTP extension:
PROPFIND/GET/PUT/DELETE/MKCOL/COPY/MOVE), never a volume mount -- so a local Docker
Desktop container and a k3s pod are reached the **same way** (they map 1:1). The
`Dav::Policy` mirrors the Code layers:

- `immutable/**` -> **read-only** (GET/PROPFIND ok; PUT/DELETE/MKCOL/COPY-dest -> 403)
- `mutable/**`   -> **read/write**

MCP2 gets read-only immutable + read/write mutable through exactly this policy.
The `magentic` CLI offers the primitives over the container's WebDAV:

```
magentic serve --root /work --port 4700   # the container serves its workspace (default CMD)
magentic ls [path] | cp <src> <dst> | rm <path>
```

This replaces bespoke fs RPCs (mm-cli `fs_read`/`fs_write`) with the standard. Backup,
integration, and merge with other code are **not** the container's job -- they happen at
the cloud/pod level.

## MCP2 stateless facade (the one seam the Cyborg sees)

`Magentic::Runtime::Mcp2` wraps vv-mcb's `Vv::Mcb::Mcp2::Facade`. The AI sees ONE
stateless tool (`discover` -> one-tool `mm_call` + virtual tools; `invoke` -> never-raise
envelope, MRTR-mapped). Actions: `run` `approve` `package` (the acts) + `ls` `get` `put`
`cp` `rm` (WebDAV fs, immutable read-only / mutable read-write). State lives in the
workspace (WebDAV mutable) + the immutable store, NEVER in the session -- so
run -> approve -> package is a sequence of self-contained invokes over persisted state.
The same facade is what the offline-laptop container and the web-online host both expose.

```
magentic mcp2 discover
magentic mcp2 invoke run     --input '{"flow":"flows/todo.yaml","out":"/work/mutable/todo"}'
magentic mcp2 invoke approve --input '{"out":"/work/mutable/todo","approver":"me"}'
```

## Identity seam: Active Pod Context + delegate ceiling

Every MCP2 request binds to an **Active Pod Context** (AdrCyborgPodRoles) -- the mandatory,
visible tuple:

```
Cyborg Pod ID | immutable Release SHA | workspace revision | principal[/ delegate]
```

It carries TWO identities: the **principal** (the human) and, when an AI acts for the
human, the **delegate**. `PodContext#allows?` enforces the human's authority CEILING: a
delegate may invoke only its `delegated` action set -- anything else is refused
(`delegated_denied`) before dispatch. `discover` is filtered to the same ceiling. A
principal acting directly has no ceiling. The default is a LOCAL context labeled
"local checkpoint -- not durable" until promoted to a real POD. Every discover/invoke
result echoes `active_pod_context`, so the tuple is always visible -- the one control
against split-brain authority. An invocation binds exactly ONE context; contexts never combine.

```
magentic mcp2 invoke run --input '{...}' \
  --pod pod-alice --principal Human:alice --delegate AI:sess-1 --delegated run,ls,get \
  --release sha256:core --rev rev-7
```
