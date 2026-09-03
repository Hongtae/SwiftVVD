# HarfBuzz source snapshot

- Upstream: <https://github.com/harfbuzz/harfbuzz>
- Release: `14.4.0`
- Commit: `36cb489cb02ce4b92099669ba9f9bea348eff93f`
- License: see [`COPYING`](COPYING)

The repository-local `Package.swift` and `Sources/HarfBuzz` files provide the
Swift Package Manager integration. The package builds the upstream
`src/harfbuzz.cc` core library, enables its FreeType bridge against
`../FreeType`, and does not enable the optional GLib, ICU, Cairo, Graphite,
platform text-service, subset, raster, vector, or GPU libraries.

This is a runtime-source snapshot rather than a complete upstream development
checkout. It retains the upstream runtime sources and headers needed by the
amalgamated build, `COPYING`, `AUTHORS`, and `THANKS`. Upstream CI
configuration, generation scripts and inputs, in-tree tests and test fonts,
benchmarks, samples, command-line utilities, generated documentation, images,
and alternate build-system files are intentionally omitted.

When updating the snapshot, check out a signed upstream release tag, update
the release and exact commit above, retain the upstream license, and rerun the
standalone package build and the root VUI build before removing the nested
upstream `.git` directory.
