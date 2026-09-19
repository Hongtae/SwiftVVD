# Local HarfBuzz changes

This document describes why the HarfBuzz source distributed by this package
differs from upstream. The imported release and exact upstream revision are
recorded in [`UPSTREAM.md`](UPSTREAM.md).

These changes support text-layout requirements that the public HarfBuzz API of
the recorded release cannot express without splitting one shaping operation
into multiple buffers. They are kept in source form so that users can inspect
the behavioral differences, and so that a later HarfBuzz update can decide
whether each change is still required.

For each change, this document records:

1. the original upstream behavior;
2. the locally modified behavior;
3. why the package distributes the modified behavior; and
4. the conditions for retaining, replacing, or removing the change during an
   update.

The local entry point is opt-in. Calls that do not request any local shaping
controls use ordinary `hb_shape`, so the default HarfBuzz path remains
unchanged.

The source-slot, boundary, and attachment changes are package extensions, not
claims that upstream's default shaping policy is generally incorrect. They
serve a layout engine that needs additional source ownership and run-boundary
information. The AAT range change is different: it corrects incorrect request
identity and precedence for overlapping ranges. These two categories are kept
separate below so downstream users can distinguish a package-specific
extension from a general behavioral correction. Upstream copyright and license
notices remain in place; see [`COPYING`](COPYING).

## Source ownership

The following adapter files are owned by this package and are not copied from
upstream:

- `Sources/HarfBuzz/include/HarfBuzz.h`
- `Sources/HarfBuzz/HarfBuzz.cc`

`HarfBuzz.cc` includes upstream `src/harfbuzz.cc` in the same translation unit.
This allows the adapter to read and temporarily configure private shaping
state. The package builds this source as a static library; these private
extensions are not an ABI contract with a system HarfBuzz installation.

The following upstream files contain intentional local changes:

| File | Local responsibility |
| --- | --- |
| `src/hb-buffer.hh` | Borrowed run boundaries and selective deleted-slot state |
| `src/hb-buffer.cc` | Initialization of the added buffer state |
| `src/hb-ot-map.hh` | Optional-ligature lookup classification |
| `src/hb-ot-map.cc` | Feature classification and conservative lookup merging |
| `src/hb-ot-layout.cc` | Transfer of lookup classification into the apply context |
| `src/hb-ot-layout-gsubgpos.hh` | Source-range enforcement for GSUB and GPOS inputs |
| `src/OT/Layout/GPOS/MarkBasePosFormat1.hh` | Boundary-aware mark-to-base cache handling |
| `src/OT/Layout/GPOS/MarkLigPosFormat1.hh` | Boundary-aware mark-to-ligature cache handling |
| `src/hb-ot-shape.cc` | Selective preservation of deleted source placeholders |
| `src/hb-aat-map.hh` | Precedence of equal AAT feature selectors |
| `src/hb-aat-map.cc` | Identity-based removal of overlapping AAT ranges |

## Extended shaping entry point

### Original upstream behavior

The public `hb_shape` entry point shapes the buffer and publishes final glyph
information and positions. It does not provide one operation that can:

- preserve an already prepared character sequence through normalization;
- override visibility for individual source characters;
- apply separate source boundaries to optional GSUB and GPOS inputs; or
- return the mark-to-parent attachment graph used while applying GPOS.

A caller can install a buffer message callback, but the public callback data
does not itself add the missing range controls. The final public positions also
do not retain the private attachment edges after offset propagation.

### Local behavior

`Sources/HarfBuzz/include/HarfBuzz.h` declares
`HBShapeWithGlyphAttachments`. The implementation in
`Sources/HarfBuzz/HarfBuzz.cc` accepts the normal font, buffer, and feature
arguments together with:

- a prepared-character preservation flag;
- one encoding policy per original source character;
- sorted optional-ligature boundaries;
- sorted positioning boundaries; and
- a mark-attachment callback.

When none of those controls is requested, the function immediately calls
`hb_shape`. Otherwise, it installs the requested state only for the synchronous
shape call. It preserves and restores:

- the previous buffer message callback and callback data;
- the previous boundary pointers and counts;
- the previous deleted-glyph policy; and
- the previous Unicode functions.

The boundary and encoding arrays are borrowed. They are never retained after
the call. If the buffer already has a message callback, that callback runs
first and its cancellation result retains precedence.

The consumer is the package shaping implementation in
[`../../Sources/VVD/Graphics/Font.swift`](../../Sources/VVD/Graphics/Font.swift).
It validates that boundaries are strictly increasing Unicode-scalar offsets
inside the input before invoking the adapter.

### Reason for distributing the change

The text layout layer needs the complete source string to remain one shaping
context while still retaining source ownership and attributed-run boundaries.
Running separate `hb_shape` calls for each run changes contextual substitution,
required ligatures, mark attachment, and surrounding-script behavior. The
extended entry point keeps one HarfBuzz buffer and makes only the required
parts of shaping range-aware.

Keeping the behavior behind one opt-in entry point also limits the effect on
other users of the bundled library. Ordinary `hb_shape` calls do not activate
the added state.

### Update decision

Retain an opt-in adapter while the consumer still needs any of the contracts
above. Individual controls can be replaced with public upstream APIs if a new
HarfBuzz release exposes equivalent behavior. Remove the entire adapter only
when all its consumers can use ordinary public APIs without splitting the
shaping context or losing source and attachment information.

When updating, also verify that every temporary buffer property is restored on
all normal completion paths. If the newer shaping API can fail or exit through
additional paths, adapt the restoration strategy before retaining this entry
point.

## Prepared-character preservation and deleted source slots

### Original upstream behavior

During normalization, HarfBuzz may compose, decompose, and reorder the input.
Later, default-ignorable glyphs are either replaced by the buffer's invisible
glyph or deleted. This behavior is appropriate for ordinary shaping output,
but it has two consequences for an externally prepared character sequence:

- the prepared character order and identity can change; and
- a deleted scalar no longer occupies a buffer slot that can carry its source
  index through subsequent substitution and positioning.

The recorded upstream version has no public option to preserve selected
deleted slots while leaving every unrelated default-ignorable character under
the normal HarfBuzz policy.

### Local behavior

When prepared-character preservation is enabled, the adapter creates temporary
Unicode functions whose compose and decompose callbacks both return false. At
the `start reorder` message, the adapter returns false to suppress reordering
of the already prepared input.

After decomposition, at the `end decompose` message, the adapter applies the
encoding policy selected by each glyph-info cluster:

- `HB_GLYPH_ENCODING_DEFAULT` leaves HarfBuzz's decision unchanged.
- `HB_GLYPH_ENCODING_VISIBLE` clears the default-ignorable state so a
  font-provided glyph remains visible.
- `HB_GLYPH_ENCODING_INVISIBLE` stores `65535` in the normalizer's private
  `var1.u32` nominal-glyph slot, marks the item default-ignorable, clears its
  hidden state, and sets the buffer's default-ignorable scratch flag.

The local `preserve_deleted_glyphs` field in `hb_buffer_t` is enabled only when
an encoding array is supplied. `src/hb-ot-shape.cc` then preserves glyph
`65535` while continuing to hide or delete all other default ignorables using
the normal policy. `src/hb-buffer.cc` initializes the field to false in buffer
reset and in the null buffer instance.

Glyph `65535` is an internal zero-advance placeholder for an original source
slot. The line-layout path can retain it while constructing source ownership;
the ordinary public shaping projection removes it. Preserving one placeholder
therefore does not make all default ignorables visible and does not add a
publicly drawn glyph.

### Reason for distributing the change

Character preparation can select a composed glyph while retaining a slot for
each original Unicode scalar. Removing one of those slots during HarfBuzz
normalization shifts later source indices and invalidates ranges used by text
layout and mark geometry. Preserving every default ignorable would also be
incorrect because joiners, variation selectors, and other controls must retain
their ordinary shaping semantics. The local policy preserves only source slots
that the caller explicitly marks as deleted and permits an explicit visible
override for a font-provided control glyph.

This is why the change is narrower than setting a global invisible glyph or
globally disabling default-ignorable handling.

### Update decision

Before retaining or reimplementing this change in a newer release, inspect the
new normalization and default-ignorable pipelines and answer all of the
following:

1. Does normalization still use `hb_glyph_info_t::var1.u32` for the pending
   nominal glyph at `end decompose`?
2. Do `start reorder` and `end decompose` still have the same timing and
   cancellation behavior?
3. Does default-ignorable deletion still happen after the placeholder becomes
   the glyph codepoint?
4. Is `65535` still safe as this package's internal deleted-source placeholder?
5. Does upstream now provide a supported way to retain selected source slots
   without retaining unrelated default ignorables?

If the answer to the last question is yes, use that public mechanism and
remove the corresponding private buffer and shaping changes. If the internal
stages changed but no equivalent API exists, preserve the behavior rather than
copying the old field access mechanically. Remove the behavior only if the
consumer no longer retains original scalar ownership through shaping.

## Optional substitution and positioning boundaries

### Original upstream behavior

The GSUB and GPOS skipping iterators in the recorded upstream version can scan
the complete shaping buffer while matching one lookup. Feature masks and
feature ranges decide where a lookup starts, but they do not independently
constrain every input consumed by an optional ligature or positioning lookup
to one attributed source run.

Dividing the text into separate buffers would create a hard boundary, but it
would also discard valid context outside that run. Applying the same hard
boundary to every GSUB lookup would additionally block required substitutions
that must continue across the source-run division.

The mark-to-base and mark-to-ligature implementations also cache the last base
glyph. That cache can bypass a newly constrained input iterator and reuse a
base from the preceding run.

### Local behavior

`hb_buffer_t` contains two borrowed arrays for the duration of the extended
shape call:

- `optional_ligature_boundaries` partitions optional GSUB lookup inputs; and
- `positioning_run_boundaries` partitions GPOS lookup inputs.

The arrays contain sorted source-scalar offsets. In
`src/hb-ot-layout-gsubgpos.hh`, each input iterator reset performs a binary
search around the current glyph's cluster and stores the containing source
interval. An input candidate outside that interval becomes a non-match. The
check occurs before the normal skip decision, so an ignored mark cannot allow
a lookup to cross a boundary accidentally.

Only input iterators are bounded. Iterators created for contextual backtrack
or lookahead are explicitly left unbounded, allowing the lookup to inspect the
surrounding shaping context.

GSUB boundaries apply only to lookups selected solely through the optional
ligature features `clig`, `dlig`, `hlig`, or `liga`:

- `src/hb-ot-map.hh` adds an `optional_ligature` lookup bit.
- `src/hb-ot-map.cc` sets it for those four feature tags.
- When duplicate lookup entries are merged, the bit is combined with logical
  AND. A lookup also selected by a required or other non-optional feature is
  therefore not restricted.
- `src/hb-ot-layout.cc` transfers the bit into the apply context.

GPOS boundaries apply to positioning lookup inputs independently of the GSUB
boundaries. In `MarkBasePosFormat1.hh` and `MarkLigPosFormat1.hh`, the input
iterator is reset at the current glyph. While positioning boundaries are
present, the cached last-base state is invalidated so it cannot bypass the
range check.

### Reason for distributing the change

Attributed text can change font or positioning properties between adjacent
source characters. Optional ligatures and kerning must respect those divisions,
but required script shaping and contextual inspection must still see the
complete neighboring text. GSUB and GPOS also need separate boundaries: a font
selection boundary and a positioning-property boundary do not always occur at
the same source offset.

The local implementation preserves one complete shaping operation, restricts
only lookup inputs that are allowed to stop at a run boundary, and keeps
required substitutions plus contextual backtrack and lookahead active. This
avoids the broader behavioral change caused by shaping each run separately.

### Update decision

Prefer a public upstream facility if it can independently constrain optional
GSUB inputs and GPOS inputs without splitting the buffer. It must also preserve
required substitutions and contextual backtrack/lookahead across the boundary.
Feature ranges alone are not equivalent unless the newer implementation
guarantees those properties for every consumed input.

If the local mechanism remains necessary, verify these private assumptions in
the newer release:

1. GSUB and GPOS still use table indices `0` and `1` in the apply context, or
   update the table selection accordingly.
2. Every forward, backward, and fast reset path used for lookup input matching
   recomputes the source interval.
3. Context iterators remain distinguishable from input iterators.
4. Lookup construction still exposes the selecting feature tag before
   duplicate lookups are merged.
5. The duplicate-merge rule still ensures that a lookup shared with a required
   feature is unrestricted.
6. Glyph clusters still carry absolute source-scalar offsets.
7. No new mark-positioning cache or fast path can select a base outside the
   current positioning interval.

Remove this change only after an equivalent upstream contract is confirmed or
after the consumer stops using independent shaping boundaries.

## GPOS mark-attachment reporting

### Original upstream behavior

HarfBuzz uses private attachment fields while applying GPOS. Mark positioning
stores an attachment type and a relative chain to the parent glyph. HarfBuzz
then propagates the attachment into final offsets. Public final glyph positions
describe where glyphs are drawn but do not expose the original parent edge.

### Local behavior

The extended adapter installs a buffer message callback and observes each
`end table GPOS ` stage. Before the private attachment information is cleared
or reduced to final offsets, it scans the position array. For entries whose
attachment type is `OT::Layout::GPOS_impl::ATTACH_TYPE_MARK` and whose chain is
nonzero, it computes:

```text
parent buffer index = mark buffer index + attachment chain
```

Valid mark and parent indices are reported synchronously to the caller. The
callback uses shaped-buffer indices, allowing the consumer to combine
connected mark ranges before publishing glyph geometry.

### Reason for distributing the change

Final offsets are insufficient to determine which base or intermediate mark
owns another mark. That relationship is needed when composed text spans fonts,
when fallback geometry is used, and when a connected mark group must be moved
as one unit. Reconstructing attachment ownership from coordinates is ambiguous
and font-dependent, while HarfBuzz already has the exact edge during GPOS.

The adapter observes that existing edge and does not alter the GPOS lookup or
the final position propagation.

### Update decision

Use an upstream attachment-query or tracing API if a newer release provides a
stable equivalent. Otherwise verify all of these private assumptions:

1. `ATTACH_TYPE_MARK` still identifies the required edge.
2. `attach_chain()` retains the same sign and relative-index convention.
3. `end table GPOS ` still runs while the attachment fields describe the
   unpropagated mark-to-parent relationship.
4. Reading the fields from a message callback remains side-effect-free.

If the private representation changes, reimplement the same callback contract
using the new representation. Do not infer parents from final coordinates as a
replacement.

## AAT overlapping feature ranges

### Original upstream behavior

The recorded upstream AAT map stores active feature requests while scanning
range start and end events. Each request has a sequence identity, but an end
event used `active_features.lsearch(event->feature)`. The search comparator
compares only feature type and setting, not the sequence identity.

When two overlapping ranges request the same type and setting but end at
different positions, ending one range can therefore remove the other active
request. Upstream also sorted otherwise equal requests by ascending sequence
before collapsing duplicates, which retained the earlier request instead of
the later call-site override.

### Local behavior

`src/hb-aat-map.cc` removes an ending feature by its unique `seq` value. Equal
selectors with different ranges can remain independently active until their
own end event.

`src/hb-aat-map.hh` orders otherwise equal requests by descending `seq` before
duplicate collapse. The latest request therefore takes precedence in the
active interval.

### Reason for distributing the change

Range-scoped font features may overlap, and a narrower call-site feature must
temporarily override an enclosing feature without deleting it. Once the inner
range ends, the enclosing request must become effective again. Removing by
type and setting loses the identity needed to implement that behavior and can
produce incorrect glyph selection after the first overlapping range ends.

This correction is a general AAT feature-map fix rather than a requirement of
the private shaping-boundary extension. It is kept separate in this document
so that it can be dropped as soon as upstream provides equivalent behavior.

### Update decision

Inspect the newer `hb-aat-map` implementation before carrying this change
forward. Remove the local edits when upstream both:

- removes range-end events by the identity of the original request, or uses an
  equivalent representation that cannot remove the wrong equal request; and
- gives the later equal request precedence within an overlapping interval.

Retain or reimplement only the missing behavior if upstream fixes one part but
not the other. The exact `seq` field and sorting implementation do not need to
remain the same; request identity and precedence are the required contracts.

## Validation when updating HarfBuzz

The focused regression coverage is located in:

- [`../../Tests/VVDTests/Graphics/FontCombiningShapingTests.swift`](../../Tests/VVDTests/Graphics/FontCombiningShapingTests.swift)
  for source-slot preservation, optional and required substitutions,
  contextual lookup behavior, positioning boundaries, default ignorables, and
  mark geometry; and
- [`../../Tests/VUITests/Rendering/Text/FontMorphFeatureTests.swift`](../../Tests/VUITests/Rendering/Text/FontMorphFeatureTests.swift)
  for AAT feature selection, call-site precedence, partial ranges, and
  overlapping ranges.

The principal guards for each local contract are:

| Contract | Regression guards |
| --- | --- |
| Prepared source slots remain addressable while public output stays filtered | `testLineOwnerRetainsRawSlotsWithoutChangingPublicShaping`, `testCharacterPreparationRetainsDeletedAndTrailingSourceSlots` |
| One deleted slot does not change unrelated default-ignorable policy | `testCanonicalDeletionDoesNotChangeOtherCharacterEncoding`, `testDefaultIgnorableEncodingKeepsFontGlyphsAndDeletedSourceSlots` |
| Optional lookup inputs stop at run boundaries without losing required or contextual shaping | `testAttributeBoundariesConstrainOptionalLigaturesWithoutSplittingShaping`, `testOptionalLookupInputsKeepContextAndSharedRequiredLookups` |
| GPOS input boundaries remain independent from GSUB boundaries | `testPositioningBoundariesKeepSubstitutionContextAndSplitGPOSInputs` |
| GPOS attachment edges preserve connected mark geometry | `testPreparedCrossFontCompositionUsesPerGlyphGeometry`, `testTableAttachmentsPreserveConnectedMarkGroups` |
| Later AAT requests override only their own overlapping ranges | `testMorphSubstitutionsKeepSourceSlotsAndCallSiteOverrides` |

For every new snapshot, classify each section above independently:

- **Upstream equivalent:** remove the local implementation and keep the
  regression test against the upstream behavior.
- **Still required:** reimplement the behavioral contract at the new internal
  control point and update this document if the mechanism changed.
- **Consumer removed:** remove the local implementation, its adapter surface,
  and the corresponding consumer-specific test together.

At minimum, validate the standalone package, the focused shaping tests, and
the root VUI build:

```sh
swift build --package-path SupportPackages/HarfBuzz
swift test --filter FontCombiningShapingTests
swift test --filter FontMorphFeatureTests
swift build --target VUI
```

Compilation alone is not sufficient. Most incompatibilities in these changes
can compile successfully while silently changing glyph selection, source
ownership, feature precedence, or mark geometry.
