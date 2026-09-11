# Local FreeType changes

The bundled version is FreeType 2.13.3. The following changes to
`src/truetype/ttgxvar.c` are local modifications:

- Restore MVAR table fields even when the requested delta is zero, and apply
  only the difference from the previously applied value to face metrics.
- Fill omitted normalized axes from the selected named instance or base face,
  and convert the complete coordinate array between normalized and design units.
- Resolve coordinates against the base face when clearing a named instance.

These changes reuse existing coordinate arrays and metric records. They add
no persistent fields or allocation. Public size metrics still require the
existing size-request step after a variation change.

## Updating the dependency

Retain these corrections until the replacement upstream source passes the
variable-font restoration guards without the local patch. Keep the guards
after removing the patch; a version number or successful coordinate readback
does not establish correct metric restoration.

From the repository root, run:

```sh
swift test --filter 'FreeTypeVariationTests|FontDesignMetricsTests'
```

The self-contained synthetic font in `FreeTypeVariationTests` exercises MVAR,
partial and empty design/blend coordinates, and named-instance transitions.
`FontDesignMetricsTests` also checks the rendering API with generated metric
tables. Diagnostic fonts and face-history comparisons are test-only. Runtime
capability checks, repeated warnings and face-replacement fallbacks are not
part of the font implementation.
