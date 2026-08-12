# magentic-runtime

The local, container-hosted runtime for **governed AI/human flows** -- the local half of
the Magentic Stack sole-developer loop (see `docs/research/AdrMagenticGapAnalysis.md`,
steps 2-3). Three explicit acts:

```
magentic run <flow.yaml> --out ./out     # AI proposes  -> candidate (result.sqlite + proposal.jsonld preview)
magentic approve --out ./out             # human promotes -> signed release-packet.json
magentic package --out ./out --image X   #             -> component.yaml + component_digest (deployable component)
```

- **run** pins a contract-set digest, a model produces a *typed row*, it is persisted to
  `result.sqlite`, and the promotion gate RE-READS the SQL evidence and stops at
  `validated` (needs approval). Writes a public `proposal.jsonld` preview -- private fields
  never cross.
- **approve** re-opens `result.sqlite`, re-reads the cited evidence, accepts the claim,
  projects the public JSON-LD, runs the privacy canary, and **signs the Release Packet**
  with the developer's local key. AI proposed; only this explicit human act releases.
- **package** produces `component.yaml` + a component `Dockerfile` (whose LABELs bind the
  workload to its release evidence), content-addresses the component, and fills the
  packet's `component_digest` via `reseal`.

Everything reuses **rr-grammar** (the GuardRail). Fail-closed at every step: a bad
proposal, missing SQL evidence, canary leak, or over-broad edge grant aborts WITHOUT
emitting a projection or packet.

```
bundle exec magentic run flows/todo.yaml --out ./out && \
bundle exec magentic approve --out ./out && \
bundle exec magentic package --out ./out --image todo-host:1
# or in Docker Desktop: docker build -t magentic-runtime . && docker run --rm -v "$PWD/out:/work" magentic-runtime
```

Linux SQLite (not OPFS); deterministic stub model connector (pluggable). Apache-2.0.
