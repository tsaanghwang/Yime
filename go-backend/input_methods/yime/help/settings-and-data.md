# Settings And Data

This is the placeholder settings-side guide for the standalone Yime tools
direction.

Use this page as the stable landing point for future work such as:

- user-facing settings windows
- data directory explanations
- deploy and reload guidance
- schema-specific configuration notes

For now, the main operational directories are:

- `%APPDATA%\PIME\Rime`
- `%LOCALAPPDATA%\PIME\Logs`
- installed shared data under `go-backend\input_methods\yime\data`

## Language-Bar Maintenance Items

The Settings menu keeps a small group of runtime-maintenance commands:

- `重新部署 Rime`: re-runs the current Rime runtime deployment so changed schema
  files or configuration can take effect. This is not a "re-import system
  lexicon" action.
- `同步 Rime 用户数据`: calls Rime's native user-data sync capability. It is
  intended for Rime-managed user data and does not include Yime-only standalone
  state such as `yime_settings_state.json`.
- `打开数据与日志文件夹`: opens the user-data, shared-data, sync, and log
  directories directly.
