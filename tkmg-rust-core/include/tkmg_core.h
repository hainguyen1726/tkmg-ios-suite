#ifndef TKMG_CORE_H
#define TKMG_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Applies CamScanner-style document enhancement filters in-place on an 0xAARRGGBB buffer
 * (equivalent to CoreGraphics byteOrder32Little | premultipliedFirst on little-endian ARM64).
 */
void tkmg_apply_document_filter_argb(
    uint32_t *pixels_ptr,
    int32_t width,
    int32_t height,
    int32_t filter_mode_ordinal,
    float brightness_offset,
    float contrast_scale
);

/**
 * Natural numeric-aware UTF-8 string comparison ("Tap 1" < "Tap 2" < "Tap 10").
 * Returns -1, 0, or 1.
 */
int32_t tkmg_natural_compare_utf8(
    const uint8_t *a_ptr,
    size_t a_len,
    const uint8_t *b_ptr,
    size_t b_len
);

#ifdef __cplusplus
}
#endif

#endif /* TKMG_CORE_H */
