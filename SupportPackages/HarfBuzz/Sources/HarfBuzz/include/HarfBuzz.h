#ifndef SWIFT_PACKAGE_HARFBUZZ_H
#define SWIFT_PACKAGE_HARFBUZZ_H

#include "../../../src/hb.h"
#include "../../../src/hb-ft.h"
#include "../../../src/hb-ot.h"
#include "../../../src/hb-raster.h"

HB_BEGIN_DECLS

typedef void (*HBGlyphAttachmentCallback)(unsigned int glyph,
                                         unsigned int parent,
                                         void *user_data);

typedef enum {
    HB_GLYPH_ENCODING_DEFAULT,
    HB_GLYPH_ENCODING_INVISIBLE,
    HB_GLYPH_ENCODING_VISIBLE
} HBGlyphEncoding;

/* Reports mark attachments in GPOS buffer order before offset propagation.
 * Prepared characters can retain their order and identity through normalization.
 * Character encodings use the original cluster coordinates and can override
 * default-ignorable glyph admission. Invisible glyphs retain their buffer slots
 * as glyph 65535 so attachment indices stay valid. Other characters retain
 * the caller's default invisible-glyph policy. Font substitution and
 * positioning tables still apply. Optional-only substitution inputs and
 * positioning inputs respect independent sorted source boundaries;
 * contextual substitution backtrack/lookahead do not.
 * Borrowed arrays and callbacks are synchronous. */
void HBShapeWithGlyphAttachments(hb_font_t *font, hb_buffer_t *buffer,
                                const hb_feature_t *features, unsigned int count,
                                hb_bool_t preserve_characters,
                                const HBGlyphEncoding *encodings, unsigned int encoding_count,
                                const unsigned int *optional_ligature_boundaries,
                                unsigned int optional_ligature_boundary_count,
                                const unsigned int *positioning_run_boundaries,
                                unsigned int positioning_run_boundary_count,
                                HBGlyphAttachmentCallback callback, void *user_data);

HB_END_DECLS

#endif
