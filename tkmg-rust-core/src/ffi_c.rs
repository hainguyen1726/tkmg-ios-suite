//! Cross-platform C-ABI FFI surface for iOS (`libtkmg_core.a`) and native consumers.

use std::cmp::Ordering;
use std::slice;

/// Applies CamScanner-style document enhancement filters in-place on an `0xAARRGGBB` pixel buffer.
///
/// Safety: `pixels_ptr` must point to a writable contiguous buffer of at least
/// `width * height` `uint32_t` (`0xAARRGGBB`) elements.
#[no_mangle]
pub unsafe extern "C" fn tkmg_apply_document_filter_argb(
    pixels_ptr: *mut u32,
    width: i32,
    height: i32,
    filter_mode_ordinal: i32,
    brightness_offset: f32,
    contrast_scale: f32,
) {
    if pixels_ptr.is_null() || width <= 0 || height <= 0 {
        return;
    }
    let Some(total) = (width as usize).checked_mul(height as usize) else {
        return;
    };
    let slice = slice::from_raw_parts_mut(pixels_ptr as *mut i32, total);
    crate::scan_filters::apply_document_filter(
        slice,
        width as usize,
        height as usize,
        filter_mode_ordinal,
        brightness_offset,
        contrast_scale,
    );
}

/// Natural numeric-aware UTF-8 filename comparator (`Tap 1`, `Tap 2`, `Tap 10`).
/// Returns `-1`, `0`, or `1`.
///
/// Safety: if `a_len > 0`, `a_ptr` must be valid for `a_len` readable bytes;
/// same for `b_ptr` and `b_len`.
#[no_mangle]
pub unsafe extern "C" fn tkmg_natural_compare_utf8(
    a_ptr: *const u8,
    a_len: usize,
    b_ptr: *const u8,
    b_len: usize,
) -> i32 {
    let bytes_a = if a_ptr.is_null() || a_len == 0 {
        &[]
    } else {
        slice::from_raw_parts(a_ptr, a_len)
    };
    let bytes_b = if b_ptr.is_null() || b_len == 0 {
        &[]
    } else {
        slice::from_raw_parts(b_ptr, b_len)
    };

    let sa = String::from_utf8_lossy(bytes_a);
    let sb = String::from_utf8_lossy(bytes_b);
    match crate::natural_sort::natural_compare(&sa, &sb) {
        Ordering::Less => -1,
        Ordering::Equal => 0,
        Ordering::Greater => 1,
    }
}

/// Computes target `(out_w, out_h)` from normalized `[tlX, tlY, trX, trY, brX, brY, blX, blY]` quad.
/// Returns `1` on success, `0` on invalid input.
#[no_mangle]
pub unsafe extern "C" fn tkmg_estimate_quad_size(
    src_w: i32,
    src_h: i32,
    quad_norm_ptr: *const f32,
    max_edge: i32,
    out_w: *mut i32,
    out_h: *mut i32,
) -> i32 {
    if quad_norm_ptr.is_null() || out_w.is_null() || out_h.is_null() || src_w < 2 || src_h < 2 {
        return 0;
    }
    let q_slice = slice::from_raw_parts(quad_norm_ptr, 8);
    let q: [f32; 8] = [
        q_slice[0], q_slice[1], q_slice[2], q_slice[3],
        q_slice[4], q_slice[5], q_slice[6], q_slice[7],
    ];
    let (w, h) = crate::perspective::estimate_quad_output_size(
        src_w as usize,
        src_h as usize,
        &q,
        max_edge.max(16) as usize,
    );
    *out_w = w as i32;
    *out_h = h as i32;
    1
}

/// Applies bilinear perspective warp from `src_ptr` (`0xAARRGGBB`) into pre-allocated `dst_ptr`.
/// Returns `1` on success, `0` on invalid/degenerate input.
#[no_mangle]
pub unsafe extern "C" fn tkmg_perspective_warp_argb(
    src_ptr: *const u32,
    src_w: i32,
    src_h: i32,
    quad_norm_ptr: *const f32,
    dst_ptr: *mut u32,
    dst_w: i32,
    dst_h: i32,
) -> i32 {
    if src_ptr.is_null()
        || dst_ptr.is_null()
        || quad_norm_ptr.is_null()
        || src_w < 2
        || src_h < 2
        || dst_w < 2
        || dst_h < 2
    {
        return 0;
    }
    let Some(src_total) = (src_w as usize).checked_mul(src_h as usize) else {
        return 0;
    };
    let Some(dst_total) = (dst_w as usize).checked_mul(dst_h as usize) else {
        return 0;
    };
    let src_slice = slice::from_raw_parts(src_ptr as *const i32, src_total);
    let dst_slice = slice::from_raw_parts_mut(dst_ptr as *mut i32, dst_total);
    let q_slice = slice::from_raw_parts(quad_norm_ptr, 8);
    let q: [f32; 8] = [
        q_slice[0], q_slice[1], q_slice[2], q_slice[3],
        q_slice[4], q_slice[5], q_slice[6], q_slice[7],
    ];
    if crate::perspective::perspective_warp_into(
        src_slice,
        src_w as usize,
        src_h as usize,
        &q,
        dst_slice,
        dst_w as usize,
        dst_h as usize,
    ) {
        1
    } else {
        0
    }
}

/// Estimates fine correction angle (degrees) to level horizontal text lines.
#[no_mangle]
pub unsafe extern "C" fn tkmg_estimate_skew_deg(
    src_ptr: *const u32,
    width: i32,
    height: i32,
    max_angle_deg: f32,
) -> f32 {
    if src_ptr.is_null() || width < 16 || height < 16 {
        return 0.0;
    }
    let Some(total) = (width as usize).checked_mul(height as usize) else {
        return 0.0;
    };
    let slice = slice::from_raw_parts(src_ptr as *const i32, total);
    crate::deskew::estimate_skew_correction_degrees(slice, width as usize, height as usize, max_angle_deg)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn c_ffi_natural_compare_orders_episodes() {
        let a = b"Tap 2.mp3";
        let b = b"Tap 10.mp3";
        let cmp = unsafe { tkmg_natural_compare_utf8(a.as_ptr(), a.len(), b.as_ptr(), b.len()) };
        assert_eq!(cmp, -1);

        let cmp_rev =
            unsafe { tkmg_natural_compare_utf8(b.as_ptr(), b.len(), a.as_ptr(), a.len()) };
        assert_eq!(cmp_rev, 1);
    }

    #[test]
    fn c_ffi_filter_handles_null_and_magic_color() {
        unsafe {
            tkmg_apply_document_filter_argb(std::ptr::null_mut(), 10, 10, 1, 0.0, 1.0);
        }
        // Light cream paper pixels + red stamp pixel
        let mut pixels = vec![0xFFEBE6DCu32; 25];
        pixels[12] = 0xFFC82828u32;
        unsafe {
            tkmg_apply_document_filter_argb(pixels.as_mut_ptr(), 5, 5, 1, 0.0, 1.0);
        }
        let stamp_r = (pixels[12] >> 16) & 0xFF;
        let stamp_b = pixels[12] & 0xFF;
        assert!(stamp_r > stamp_b + 60);
    }
}
