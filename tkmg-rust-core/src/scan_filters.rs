//! High-performance document image enhancement filters compiled to native ARM64.

#[inline]
fn clamp_byte(v: f32) -> i32 {
    v.round().clamp(0.0, 255.0) as i32
}

#[inline]
fn rgb_luma(px: i32) -> i32 {
    let r = (px >> 16) & 0xFF;
    let g = (px >> 8) & 0xFF;
    let b = px & 0xFF;
    (77 * r + 150 * g + 29 * b) >> 8
}

fn build_luma_and_integral(pixels: &[i32], width: usize, height: usize) -> (Vec<i32>, Vec<i64>) {
    let total = pixels.len();
    let mut lumas = vec![0i32; total];
    let stride = width + 1;
    let mut integral = vec![0i64; stride * (height + 1)];

    for y in 0..height {
        let mut row_sum = 0i64;
        let y_off = y * width;
        let i_row = (y + 1) * stride;
        let prev_row = y * stride;
        for x in 0..width {
            let l = rgb_luma(pixels[y_off + x]);
            lumas[y_off + x] = l;
            row_sum += l as i64;
            integral[i_row + x + 1] = integral[prev_row + x + 1] + row_sum;
        }
    }
    (lumas, integral)
}

pub fn apply_document_filter(
    pixels: &mut [i32],
    width: usize,
    height: usize,
    mode_ordinal: i32,
    brightness_offset: f32,
    contrast_scale: f32,
) {
    if pixels.is_empty() || width == 0 || height == 0 || pixels.len() < width * height {
        return;
    }

    match mode_ordinal {
        0 => {
            if brightness_offset != 0.0 || (contrast_scale - 1.0).abs() > 1e-4 {
                apply_brightness_contrast(pixels, brightness_offset, contrast_scale);
            }
        }
        1 => apply_magic_color(pixels, width, height, brightness_offset, contrast_scale),
        2 => apply_adaptive_bw(pixels, width, height, brightness_offset, contrast_scale),
        3 => apply_grayscale_auto_levels(pixels, brightness_offset, contrast_scale),
        4 => apply_super_sharp(pixels, width, height, brightness_offset, contrast_scale),
        _ => {}
    }
}

fn apply_brightness_contrast(pixels: &mut [i32], brightness_offset: f32, contrast_scale: f32) {
    let add = brightness_offset * 255.0;
    for px in pixels.iter_mut() {
        let c = *px;
        let a = (c >> 24) & 0xFF;
        let r = clamp_byte((((c >> 16) & 0xFF) as f32 - 128.0) * contrast_scale + 128.0 + add);
        let g = clamp_byte((((c >> 8) & 0xFF) as f32 - 128.0) * contrast_scale + 128.0 + add);
        let b = clamp_byte(((c & 0xFF) as f32 - 128.0) * contrast_scale + 128.0 + add);
        *px = (a << 24) | (r << 16) | (g << 8) | b;
    }
}

fn apply_grayscale_auto_levels(pixels: &mut [i32], brightness_offset: f32, contrast_scale: f32) {
    let mut hist = [0usize; 256];
    let mut lumas = vec![0i32; pixels.len()];
    for (i, &c) in pixels.iter().enumerate() {
        let l = rgb_luma(c);
        lumas[i] = l;
        hist[l.clamp(0, 255) as usize] += 1;
    }

    let total = pixels.len() as f32;
    let low_target = (total * 0.02).round() as usize;
    let high_target = (total * 0.90).round() as usize;
    let mut acc = 0usize;
    let mut low = 0i32;
    let mut high = 255i32;
    let mut found_low = false;

    for (val, &cnt) in hist.iter().enumerate() {
        acc += cnt;
        if !found_low && acc >= low_target {
            low = val as i32;
            found_low = true;
        }
        if acc >= high_target {
            high = val as i32;
            break;
        }
    }
    if high < low + 24 {
        high = low + 24;
    }
    let span = (high - low) as f32;
    let add = brightness_offset * 255.0;
    let gain = contrast_scale * 1.12;

    for (i, px) in pixels.iter_mut().enumerate() {
        let stretched = ((lumas[i] - low) as f32 / span) * 255.0;
        let v = clamp_byte((stretched - 128.0) * gain + 128.0 + add);
        let a = *px & (0xFF << 24);
        *px = a | (v << 16) | (v << 8) | v;
    }
}

fn apply_adaptive_bw(
    pixels: &mut [i32],
    width: usize,
    height: usize,
    brightness_offset: f32,
    contrast_scale: f32,
) {
    let (lumas, integral) = build_luma_and_integral(pixels, width, height);
    let stride = width + 1;
    let radius = (width.min(height) / 34).max(10);
    let base_ratio = (0.87 - brightness_offset * 0.18).clamp(0.65, 0.95);
    let ink_sharp = contrast_scale.clamp(0.6, 2.0);
    let ramp = 34.0 / ink_sharp;

    for y in 0..height {
        let y1 = y.saturating_sub(radius);
        let y2 = (y + radius).min(height - 1);
        let top_row = y1 * stride;
        let bot_row = (y2 + 1) * stride;
        let row_off = y * width;

        for x in 0..width {
            let x1 = x.saturating_sub(radius);
            let x2 = (x + radius).min(width - 1);
            let count = ((x2 - x1 + 1) * (y2 - y1 + 1)) as f32;
            let sum = integral[bot_row + x2 + 1] - integral[bot_row + x1]
                - integral[top_row + x2 + 1]
                + integral[top_row + x1];
            let local_mean = (sum as f32) / count;
            let lum = lumas[row_off + x] as f32;
            let threshold = local_mean * base_ratio;

            let out_val = if lum >= threshold {
                255i32
            } else if lum <= threshold - ramp {
                16i32
            } else {
                let t = ((threshold - lum) / ramp).clamp(0.0, 1.0);
                (255.0 - t * 239.0).round().clamp(16.0, 255.0) as i32
            };
            let a = pixels[row_off + x] & (0xFF << 24);
            pixels[row_off + x] = a | (out_val << 16) | (out_val << 8) | out_val;
        }
    }
}

fn apply_magic_color(
    pixels: &mut [i32],
    width: usize,
    height: usize,
    brightness_offset: f32,
    contrast_scale: f32,
) {
    let (lumas, integral) = build_luma_and_integral(pixels, width, height);
    let stride = width + 1;
    let radius = (width.min(height) / 26).max(14);
    let bright_add = brightness_offset * 255.0;
    let gain = 1.20 * contrast_scale;

    for y in 0..height {
        let y1 = y.saturating_sub(radius);
        let y2 = (y + radius).min(height - 1);
        let top_row = y1 * stride;
        let bot_row = (y2 + 1) * stride;
        let row_off = y * width;

        for x in 0..width {
            let x1 = x.saturating_sub(radius);
            let x2 = (x + radius).min(width - 1);
            let count = ((x2 - x1 + 1) * (y2 - y1 + 1)) as f32;
            let sum = integral[bot_row + x2 + 1] - integral[bot_row + x1]
                - integral[top_row + x2 + 1]
                + integral[top_row + x1];
            let local_paper = (((sum as f32) / count) * 1.04).max(90.0);

            let c = pixels[row_off + x];
            let a = (c >> 24) & 0xFF;
            let r = (c >> 16) & 0xFF;
            let g = (c >> 8) & 0xFF;
            let b = c & 0xFF;

            let max_ch = r.max(g.max(b));
            let min_ch = r.min(g.min(b));
            let chroma = max_ch - min_ch;

            let norm_scale = 248.0 / local_paper;
            let mut nr = (r as f32) * norm_scale;
            let mut ng = (g as f32) * norm_scale;
            let mut nb = (b as f32) * norm_scale;

            if chroma < 26 && (lumas[row_off + x] as f32) >= local_paper * 0.88 {
                nr = nr * 0.35 + 255.0 * 0.65;
                ng = ng * 0.35 + 255.0 * 0.65;
                nb = nb * 0.35 + 255.0 * 0.65;
            } else {
                let mid = (nr + ng + nb) / 3.0;
                nr = mid + (nr - mid) * 1.25;
                ng = mid + (ng - mid) * 1.25;
                nb = mid + (nb - mid) * 1.25;
            }

            let out_r = clamp_byte((nr - 128.0) * gain + 128.0 + bright_add);
            let out_g = clamp_byte((ng - 128.0) * gain + 128.0 + bright_add);
            let out_b = clamp_byte((nb - 128.0) * gain + 128.0 + bright_add);
            pixels[row_off + x] = (a << 24) | (out_r << 16) | (out_g << 8) | out_b;
        }
    }
}

fn apply_super_sharp(
    pixels: &mut [i32],
    width: usize,
    height: usize,
    brightness_offset: f32,
    contrast_scale: f32,
) {
    let src = pixels.to_vec();
    let add = brightness_offset * 255.0;
    let contrast = contrast_scale * 1.18;

    for y in 0..height {
        let row_off = y * width;
        for x in 0..width {
            let c = src[row_off + x];
            let a = (c >> 24) & 0xFF;
            let r = ((c >> 16) & 0xFF) as f32;
            let g = ((c >> 8) & 0xFF) as f32;
            let b = (c & 0xFF) as f32;

            let (sr, sg, sb) = if x >= 1 && x + 1 < width && y >= 1 && y + 1 < height {
                let left = src[row_off + x - 1];
                let right = src[row_off + x + 1];
                let up = src[(y - 1) * width + x];
                let down = src[(y + 1) * width + x];

                let avg_r = (((left >> 16) & 0xFF)
                    + ((right >> 16) & 0xFF)
                    + ((up >> 16) & 0xFF)
                    + ((down >> 16) & 0xFF)) as f32
                    * 0.25;
                let avg_g = (((left >> 8) & 0xFF)
                    + ((right >> 8) & 0xFF)
                    + ((up >> 8) & 0xFF)
                    + ((down >> 8) & 0xFF)) as f32
                    * 0.25;
                let avg_b = ((left & 0xFF) + (right & 0xFF) + (up & 0xFF) + (down & 0xFF))
                    as f32
                    * 0.25;

                (
                    r + (r - avg_r) * 0.75,
                    g + (g - avg_g) * 0.75,
                    b + (b - avg_b) * 0.75,
                )
            } else {
                (r, g, b)
            };

            let fr = clamp_byte((sr - 128.0) * contrast + 134.0 + add);
            let fg = clamp_byte((sg - 128.0) * contrast + 134.0 + add);
            let fb = clamp_byte((sb - 128.0) * contrast + 134.0 + add);
            pixels[row_off + x] = (a << 24) | (fr << 16) | (fg << 8) | fb;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rust_bw_turns_paper_white_and_ink_dark() {
        let width = 40;
        let height = 40;
        let mut pixels = vec![0i32; width * height];
        for y in 0..height {
            for x in 0..width {
                pixels[y * width + x] = if (15..=22).contains(&x) && (15..=22).contains(&y) {
                    0xFF202020u32 as i32
                } else {
                    let shade = 0xB8 + (((x + y) % 30) as i32);
                    (0xFF << 24) | (shade << 16) | (shade << 8) | shade
                };
            }
        }
        apply_document_filter(&mut pixels, width, height, 2, 0.0, 1.0);
        assert_eq!(pixels[2 * width + 2] & 0xFF, 255);
        assert!((pixels[18 * width + 18] & 0xFF) < 40);
    }

    #[test]
    fn rust_magic_color_preserves_red_stamp() {
        let width = 48;
        let height = 48;
        let mut pixels = vec![0xFFC4C4C4u32 as i32; width * height];
        for y in 18..=28 {
            for x in 18..=28 {
                pixels[y * width + x] = 0xFFD42A2Au32 as i32;
            }
        }
        apply_document_filter(&mut pixels, width, height, 1, 0.0, 1.0);
        let stamp = pixels[22 * width + 22];
        let r = (stamp >> 16) & 0xFF;
        let g = (stamp >> 8) & 0xFF;
        let b = stamp & 0xFF;
        assert!(r > g + 60 && r > b + 60);
        assert!(((pixels[2 * width + 2] >> 16) & 0xFF) >= 220);
    }
}
