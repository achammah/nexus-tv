# BUILD-MODE — Nexus TV (native tvOS + macOS, archetype 4)

| Row | Value |
|---|---|
| Archetype | 4, native app (SwiftUI, XcodeGen), no hosted part |
| Mode | ENGINE: parallel lanes in git worktrees, the builder (appletv-builder) merges and judges |
| Authority | lead msg 00b0de47 ("Run it in parallel with your own sub-lanes in separate worktrees, disjoint files, you merge"), owner "Please finish this all faster" |
| Lanes | images (sonnet) · sources (sonnet) · live-page (the lead's lane) — partition: docs/lane-dag.json |
| Preview owner | the builder: screenshots by window id (Mac), simulator screenshots (tvOS) |
| Repo | git from creation; master = private, gh = public tree |
| Contract deltas | none to the platform; Shared/Core gains a Source protocol (sources lane) and an image loader + logo resolver (images lane) |
