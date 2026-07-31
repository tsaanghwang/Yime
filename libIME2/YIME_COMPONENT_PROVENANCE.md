# Yime libIME2 component provenance

This directory was imported into the Yime repository from:

- repository: `https://github.com/tsaanghwang/libIME2.git`
- base commit: `e7e11888343a4fd72b8610bc067109ed16d57def`
- integration mode: tracked in-tree source

The upstream repository preserves history through the base commit. Yime commits
after this import are protected by `tools/check-libime2-change-boundary.ps1`:
ordinary component commits touch only `libIME2/**` and carry a
`LibIME2-Change:` trailer. This makes it possible to reconstruct a future
standalone repository by starting at the base commit and applying the
path-filtered Yime component history after the vendor transition.
