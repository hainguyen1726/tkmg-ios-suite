pub mod ffi_c;
pub mod natural_sort;
pub mod perspective;
pub mod scan_filters;

#[cfg(target_os = "android")]
mod android_jni {
    use jni::objects::{JClass, JFloatArray, JIntArray, JString, ReleaseMode};
    use jni::sys::{jboolean, jfloat, jint};
    use jni::JNIEnv;

    #[no_mangle]
    pub extern "system" fn Java_com_tkmg_scanner_util_RustScanNative_nativeApplyDocumentFilter(
        mut env: JNIEnv,
        _class: JClass,
        pixels: JIntArray,
        width: jint,
        height: jint,
        filter_mode_ordinal: jint,
        brightness_offset: jfloat,
        contrast_scale: jfloat,
    ) {
        if width <= 0 || height <= 0 {
            return;
        }
        // SAFETY: GetIntArrayElements returns a contiguous jint slice valid until release.
        if let Ok(mut elements) = unsafe { env.get_array_elements(&pixels, ReleaseMode::CopyBack) } {
            let len = elements.len();
            let slice = unsafe { std::slice::from_raw_parts_mut(elements.as_mut_ptr(), len) };
            crate::scan_filters::apply_document_filter(
                slice,
                width as usize,
                height as usize,
                filter_mode_ordinal,
                brightness_offset,
                contrast_scale,
            );
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_com_tkmg_scanner_util_RustScanNative_nativePerspectiveWarp(
        mut env: JNIEnv,
        _class: JClass,
        src_pixels: JIntArray,
        src_w: jint,
        src_h: jint,
        quad_norm: JFloatArray,
        dst_pixels: JIntArray,
        dst_w: jint,
        dst_h: jint,
    ) -> jboolean {
        if src_w < 2 || src_h < 2 || dst_w < 2 || dst_h < 2 {
            return 0;
        }
        let mut q = [0.0f32; 8];
        if env.get_float_array_region(&quad_norm, 0, &mut q).is_err() {
            return 0;
        }
        let Ok(src_el) = (unsafe { env.get_array_elements(&src_pixels, ReleaseMode::NoCopyBack) }) else {
            return 0;
        };
        let Ok(mut dst_el) = (unsafe { env.get_array_elements(&dst_pixels, ReleaseMode::CopyBack) }) else {
            return 0;
        };
        let src_slice = unsafe { std::slice::from_raw_parts(src_el.as_ptr(), src_el.len()) };
        let dst_slice = unsafe { std::slice::from_raw_parts_mut(dst_el.as_mut_ptr(), dst_el.len()) };
        let ok = crate::perspective::perspective_warp_into(
            src_slice,
            src_w as usize,
            src_h as usize,
            &q,
            dst_slice,
            dst_w as usize,
            dst_h as usize,
        );
        if ok { 1 } else { 0 }
    }

    #[no_mangle]
    pub extern "system" fn Java_com_tkmg_player_util_RustAudioCore_nativeNaturalCompare(
        mut env: JNIEnv,
        _class: JClass,
        a: JString,
        b: JString,
    ) -> jint {
        let sa: String = match env.get_string(&a) {
            Ok(s) => s.into(),
            Err(_) => return 0,
        };
        let sb: String = match env.get_string(&b) {
            Ok(s) => s.into(),
            Err(_) => return 0,
        };
        match crate::natural_sort::natural_compare(&sa, &sb) {
            std::cmp::Ordering::Less => -1,
            std::cmp::Ordering::Equal => 0,
            std::cmp::Ordering::Greater => 1,
        }
    }
}
