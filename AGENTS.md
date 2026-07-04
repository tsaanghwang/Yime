# Agent Constraints

These rules exist to prevent AI-assisted edits from destabilizing PIME/Rime host integration.

- Do not change native Rime candidate paging ownership without an explicit user request. `nativeBackend.UsesBackendCandidatePaging()` must keep returning `true`; real Rime sessions own their paging after activation and language-bar/menu clicks.
- Do not use Go-side candidate slicing as a shortcut to force the visible candidate count for native Rime sessions. Fix candidate count through Rime configuration/deploy/reload paths instead.
- Do not treat language-bar submenu depth as inherently unsafe. PIME may support nested menus, but changes to nested menu structure must be backed by a regression test that exercises the exact host click path.
- Before changing reverse lookup menu IDs, language-bar command IDs, candidate setting menu structure, or native backend click/activation behavior, add or update a regression test for the concrete failure path being protected. In particular, guard against clicking language-bar items such as "音元拼音" causing the host application to exit.
- The guard test `TestNativeBackendKeepsRimeOwnedCandidatePaging` is intentional. Do not weaken or remove it to make an unrelated candidate-window change pass.
