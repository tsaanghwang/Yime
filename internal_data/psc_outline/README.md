# PSC outline internal snapshot

This directory is the self-contained evidence snapshot used by Yime's offline
PSC transcription review and future pronunciation audits. It is not packaged
with the Windows input runtime.

Contents:

- `psc_outline_ocr.sqlite3`: portable review database, including manual review
  decisions and structured neutral-tone, erhua, orthoepy, passage-pronunciation,
  and rare-word evidence;
- `pages/`: 197 hash-verified OCR page images used by the review UI;
- `source_documents/`: seven hash-verified source documents referenced by the
  database;
- `snapshot_manifest.json`: authorization, transformation, table-count, size,
  and SHA-256 lock for the snapshot.

Run the review UI from the Yime repository root with:

```powershell
python .\tools\psc_outline_review_tool.py
```

Verify the complete snapshot before and after any reviewed database change:

```powershell
python .\tools\verify_psc_outline_snapshot.py
```

The snapshot was created by a one-time, user-authorized transfer from a
detached non-Git working directory. Backup databases, SQLite WAL/SHM sidecars,
caches, legacy launchers, and duplicate scripts were intentionally excluded.
No normal Yime tool searches for or falls back to that former machine-local
directory.
