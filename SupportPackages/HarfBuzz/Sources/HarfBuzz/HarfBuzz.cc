#include "../../src/harfbuzz.cc"
#include "include/HarfBuzz.h"

namespace {
struct AttachmentCapture {
    HBGlyphAttachmentCallback callback;
    void *data;
    hb_buffer_message_func_t previous;
    void *previousData;
    bool preserveCharacters;
    const HBGlyphEncoding *encodings;
    unsigned int encodingCount;
};

hb_bool_t preserveComposition(hb_unicode_funcs_t *, hb_codepoint_t,
                             hb_codepoint_t, hb_codepoint_t *, void *) { return false; }
hb_bool_t preserveDecomposition(hb_unicode_funcs_t *, hb_codepoint_t,
                               hb_codepoint_t *, hb_codepoint_t *, void *) { return false; }

hb_bool_t captureAttachments(hb_buffer_t *buffer, hb_font_t *font,
                            const char *message, void *data) {
    const auto& capture = *static_cast<AttachmentCapture *>(data);
    if (capture.previous && !capture.previous(buffer, font, message, capture.previousData))
        return false;
    if (capture.encodings && strcmp(message, "end decompose") == 0) {
        for (unsigned i = 0; i < buffer->len; ++i) {
            auto& info = buffer->info[i];
            if (info.cluster >= capture.encodingCount) continue;
            switch (capture.encodings[info.cluster]) {
                case HB_GLYPH_ENCODING_INVISIBLE:
                    // The bundled normalizer stores the nominal glyph here
                    // until substitution starts. Keep the original source slot.
                    info.var1.u32 = 65535;
                    _hb_glyph_info_set_default_ignorable(&info);
                    _hb_glyph_info_unhide(&info);
                    buffer->scratch_flags |= HB_BUFFER_SCRATCH_FLAG_HAS_DEFAULT_IGNORABLES;
                    break;
                case HB_GLYPH_ENCODING_VISIBLE:
                    _hb_glyph_info_clear_default_ignorable(&info);
                    break;
                case HB_GLYPH_ENCODING_DEFAULT: break;
            }
        }
    }
    if (capture.preserveCharacters && strcmp(message, "start reorder") == 0)
        return false;
    // This adapter belongs to the bundled shaper. Its positioning phase and
    // private attachment fields must be reviewed together when it is updated.
    if (capture.callback && strncmp(message, "end table GPOS ", 15) == 0) {
        for (unsigned i = 0; i < buffer->len; ++i) {
            const auto& position = buffer->pos[i];
            if (position.attach_type() != OT::Layout::GPOS_impl::ATTACH_TYPE_MARK ||
                position.attach_chain() == 0) continue;
            const int parent = int(i) + position.attach_chain();
            if (parent >= 0 && unsigned(parent) < buffer->len)
                capture.callback(i, unsigned(parent), capture.data);
        }
    }
    return true;
}
}

void HBShapeWithGlyphAttachments(hb_font_t *font, hb_buffer_t *buffer,
                                const hb_feature_t *features, unsigned int count,
                                hb_bool_t preserveCharacters,
                                const HBGlyphEncoding *encodings, unsigned int encodingCount,
                                const unsigned int *optionalLigatureBoundaries,
                                unsigned int optionalLigatureBoundaryCount,
                                const unsigned int *positioningRunBoundaries,
                                unsigned int positioningRunBoundaryCount,
                                HBGlyphAttachmentCallback callback, void *data) {
    if (!encodingCount) encodings = nullptr;
    if (!callback && !preserveCharacters && !encodings && !optionalLigatureBoundaryCount &&
        !positioningRunBoundaryCount) {
        hb_shape(font, buffer, features, count); return;
    }
    AttachmentCapture capture{callback, data, buffer->message_func, buffer->message_data,
                              preserveCharacters != 0, encodings, encodingCount};
    auto previousDeletedGlyphs = buffer->preserve_deleted_glyphs;
    // Explicit deleted slots survive hiding without changing the default
    // encoding policy of other source characters in the same buffer.
    if (encodings) buffer->preserve_deleted_glyphs = true;
    hb_unicode_funcs_t *originalUnicode = nullptr;
    if (preserveCharacters) {
        originalUnicode = hb_unicode_funcs_reference(hb_buffer_get_unicode_funcs(buffer));
        auto unicode = hb_unicode_funcs_create(originalUnicode);
        hb_unicode_funcs_set_compose_func(unicode, preserveComposition, nullptr, nullptr);
        hb_unicode_funcs_set_decompose_func(unicode, preserveDecomposition, nullptr, nullptr);
        hb_buffer_set_unicode_funcs(buffer, unicode);
        hb_unicode_funcs_destroy(unicode);
    }
    // Borrow the observation slot without destroying an existing observer.
    // Shaping does not release or reset the caller-owned buffer.
    buffer->message_func = captureAttachments;
    buffer->message_data = &capture;
    auto previousBoundaries = buffer->optional_ligature_boundaries;
    auto previousBoundaryCount = buffer->optional_ligature_boundary_count;
    auto previousPositioningBoundaries = buffer->positioning_run_boundaries;
    auto previousPositioningBoundaryCount = buffer->positioning_run_boundary_count;
    buffer->optional_ligature_boundaries = optionalLigatureBoundaries;
    buffer->optional_ligature_boundary_count = optionalLigatureBoundaryCount;
    buffer->positioning_run_boundaries = positioningRunBoundaries;
    buffer->positioning_run_boundary_count = positioningRunBoundaryCount;
    hb_shape(font, buffer, features, count);
    buffer->optional_ligature_boundaries = previousBoundaries;
    buffer->optional_ligature_boundary_count = previousBoundaryCount;
    buffer->positioning_run_boundaries = previousPositioningBoundaries;
    buffer->positioning_run_boundary_count = previousPositioningBoundaryCount;
    buffer->message_func = capture.previous;
    buffer->message_data = capture.previousData;
    buffer->preserve_deleted_glyphs = previousDeletedGlyphs;
    if (originalUnicode) {
        hb_buffer_set_unicode_funcs(buffer, originalUnicode);
        hb_unicode_funcs_destroy(originalUnicode);
    }
}
