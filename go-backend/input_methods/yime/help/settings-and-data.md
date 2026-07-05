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

## External Tool Windows And Input Methods

Yime's tool windows are independent external windows. On Windows, moving the
focus into a different application or top-level window can restore that
window's own input-method context instead of carrying forward the IME that was
active in the previous host.

Because of that, Yime does not guarantee that opening a standalone tool such as
the lexicon manager will keep `音元拼音` active automatically. Forcing the
external window back to Yime is possible only through much more intrusive TSF
or focus manipulation, and in practice that has proven fragile: it can switch
focus unexpectedly, collapse the language-bar flow, or destabilize the host.

The current product direction is therefore:

- keep standalone tools stable and easy to reopen
- reduce reliance on long-form text entry inside those windows
- prefer batch edit, import/export, source-file editing, and other workflows
  that fit normal Windows input-method behavior
