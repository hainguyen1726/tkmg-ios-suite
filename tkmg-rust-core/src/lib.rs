pub mod ffi_c;
pub mod natural_sort;
pub mod scan_filters;

#[cfg(target_os = "android")]
mod android_jni {
    use jni::objects::{JClass, JIntArray, JString, ReleaseMode};
    use jni::sys::{jfloat, jint};
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
