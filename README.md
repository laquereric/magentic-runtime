# magentic-runtime

The local, container-hosted runtime for **governed AI/human flows** -- step 2 of the
Magentic Stack sole-developer platform (see `docs/research/AdrMagenticGapAnalysis.md`).

A flow can only emit **typed proposals under a pinned contract-set digest**. One
`magentic run flow.yaml` produces:

- `result.sqlite` -- the local evidence database (ordinary Linux SQLite, not OPFS)
- `proposal.jsonld` -- the public JSON-LD projection (private fields never cross)
- `release-packet.json` -- the signed Release Packet binding flow + contract-set +
  provenance + public projection + edge grant

It reuses **rr-grammar** (the GuardRail): typed proposal -> re-read SQL evidence ->
immutable claim -> project -> privacy canary -> Release Packet. Fail-closed at every
step (bad proposal, missing evidence, canary leak, or over-broad grant aborts the run).

```
bundle exec magentic run flows/todo.yaml --out ./out
# or in Docker Desktop:
docker build -t magentic-runtime . && docker run --rm -v "$PWD/out:/work" magentic-runtime
```

Apache-2.0.
