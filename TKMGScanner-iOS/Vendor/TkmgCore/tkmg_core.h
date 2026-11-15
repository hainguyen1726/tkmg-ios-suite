#ifndef TKMG_CORE_H
#define TKMG_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void tkmg_apply_document_filter_argb(
    uint32_t *pixels_ptr,
    int32_t width,
    int32_t height,
    int32_t filter_mode_ordinal,
    float brightness_offset,
    float contrast_scale
);

int32_t tkmg_natural_compare_utf8(
    const uint8_t *a_ptr,
    size_t a_len,
    const uint8_t *b_ptr,
    size_t b_len
);

int32_t tkmg_estimate_quad_size(
    int32_t src_w,
    int32_t src_h,
    const float *quad_norm_ptr,
    int32_t max_edge,
    int32_t *out_w,
    int32_t *out_h
);

int32_t tkmg_perspective_warp_argb(
    const uint32_t *src_ptr,
    int32_t src_w,
    int32_t src_h,
    const float *quad_norm_ptr,
    uint32_t *dst_ptr,
    int32_t dst_w,
    int32_t dst_h
);

#ifdef __cplusplus
}
#endif

#endif /* TKMG_CORE_H */
