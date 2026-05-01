This folder contains the source-of-truth SQLite workspace for pinyin imports.

Why it lives here instead of under `pinyin/`:

- `pinyin/` mainly stores rules, static source files, and test fixtures.
- The SQLite database is a generated internal artifact used for import, audit, and export.
- Keeping the database, schema, and builder together avoids scattering mutable data files across the repo root.

Current contents:

- `schema.sql`: SQLite schema for raw single-character and phrase pinyin source data.
- `build_source_pinyin_db.py`: Initializes the database and imports upstream source text files.
- `source_pinyin.db`: Generated SQLite database file.

Default upstream source:

- sibling `pinyin-data` repo, typically `../pinyin-data/pinyin.txt`

Optional future phrase source:

- phrase pinyin source repo, if present alongside this workspace
