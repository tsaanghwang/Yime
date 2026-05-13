This folder contains the source-of-truth SQLite workspace for pinyin imports.

Why it lives here instead of under `pinyin/`:

- `pinyin/` mainly stores rules, static source files, and test fixtures.
- The SQLite database is a generated internal artifact used for import, audit, and export.
- Keeping the database, schema, and builder together avoids scattering mutable data files across the repo root.

Current contents:

- `schema.sql`: SQLite schema for raw single-character and phrase pinyin source data.
- `build_source_pinyin_db.py`: Initializes the database and imports upstream source text files.
- `source_pinyin.db`: Generated SQLite database file.
- `PATCH_POLICY.md`: When to patch numeric pinyin facts versus canonical yime codes.
- `export_yaml_lexicon_json.py`: Standalone `.yaml -> .json` export entrypoint, independent from the SQLite rebuild chain.

Default generated location:

- `c:/dev/Yime/.generated/source_pinyin.db`

Override options:

- set `YIME_SOURCE_PINYIN_DB` to point tools at an external SQLite file
- if `.generated/source_pinyin.db` exists, rebuild/import helpers prefer it over the legacy tracked path

Default upstream source:

- sibling `pinyin-data` repo, typically `../pinyin-data/pinyin.txt`

Optional future phrase source:

- phrase pinyin source repo, if present alongside this workspace

Independent YAML export:

- To rebuild `danzi_pinyin.json` / `duozi_pinyin.json` without touching the SQLite path, run:

  `c:/dev/Yime/.venv/Scripts/python.exe internal_data/pinyin_source_db/export_yaml_lexicon_json.py`

- Default YAML sources now live under `internal_data/pinyin_source_db/lexicon_sources/`
- Default exported JSON files now live under `internal_data/pinyin_source_db/lexicon_exports/`
