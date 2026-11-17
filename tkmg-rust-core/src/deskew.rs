//! Fast offline document text skew estimation via weighted projection profile variance.
//! Designed for real-time mobile use (~10–25ms on downsampled document luminance).

const MAX_WORK_DIM: usize = 240;

#[inline]
fn argb_luma(argb: u32) -> f32 {
    let r = ((argb >> 16) & 0xFF) as f32;
    let g = ((argb >> 8) & 0xFF) as f32;
    let b = (argb & 0xFF) as f32;
    0.299 * r + 0.587 * g + 0.114 * b
}

fn projection_energy(points: &[(f32, f32, f32)], alpha_deg: f32, half_diag: f32, num_bins: usize) -> f64 {
    let rad = (alpha_deg as f64) * std::f64::consts::PI / 180.0;
    let sin_a = rad.sin() as f32;
    let cos_a = rad.cos() as f32;

    let mut bins = vec![0.0f64; num_bins];
    for &(dx, dy, w) in points {
        let proj = -dx * sin_a + dy * cos_a + half_diag;
        if proj < 0.0 {
            continue;
        }
        let idx = proj.floor() as usize;
        if idx + 1 >= num_bins {
            continue;
        }
        let frac = (proj - idx as f32) as f64;
        let wf = w as f64;
        bins[idx] += wf * (1.0 - frac);
        bins[idx + 1] += wf * frac;
    }

    let mut energy = 0.0f64;
    for v in bins {
        energy += v * v;
    }
    energy
}

/// Estimates the fine correction angle (in degrees, UIKit/top-left clockwise-positive convention)
/// needed to level tilted horizontal text lines inside an `0xAARRGGBB` document image.
///
/// For example, if text lines slope downward to the right (+6 deg clockwise tilt),
/// this returns approximately `-6.0` so applying `rotate(correction_deg)` makes them horizontal.
pub fn estimate_skew_correction_degrees(
    pixels: &[i32],
    width: usize,
    height: usize,
    max_angle_deg: f32,
) -> f32 {
    let total = match width.checked_mul(height) {
        Some(t) if width >= 16 && height >= 16 && pixels.len() >= t => t,
        _ => return 0.0,
    };
    let _ = total;

    let max_ang = max_angle_deg.clamp(1.0, 20.0);

    // Inspect central 88% to reduce desk/outer-margin noise.
    let x0 = (width as f32 * 0.06) as usize;
    let x1 = ((width as f32 * 0.94) as usize).max(x0 + 8).min(width);
    let y0 = (height as f32 * 0.06) as usize;
    let y1 = ((height as f32 * 0.94) as usize).max(y0 + 8).min(height);

    let roi_w = x1 - x0;
    let roi_h = y1 - y0;
    let longest = roi_w.max(roi_h);
    let scale = if longest > MAX_WORK_DIM {
        MAX_WORK_DIM as f32 / longest as f32
    } else {
        1.0
    };
    let dw = ((roi_w as f32 * scale).round() as usize).max(16);
    let dh = ((roi_h as f32 * scale).round() as usize).max(16);

    let mut luma = vec![0.0f32; dw * dh];
    for dy in 0..dh {
        let sy = (y0 + (dy * roi_h) / dh).min(height - 1);
        let row_off = sy * width;
        for dx in 0..dw {
            let sx = (x0 + (dx * roi_w) / dw).min(width - 1);
            luma[dy * dw + dx] = argb_luma(pixels[row_off + sx] as u32);
        }
    }

    // Collect sparse vertical-gradient + ink transition features around the center.
    let cx = (dw as f32 - 1.0) * 0.5;
    let cy = (dh as f32 - 1.0) * 0.5;
    let mut points: Vec<(f32, f32, f32)> = Vec::with_capacity(dw * dh / 4);

    for y in 1..(dh - 1) {
        for x in 1..(dw - 1) {
            let top = luma[(y - 1) * dw + x];
            let bot = luma[(y + 1) * dw + x];
            let left = luma[y * dw + (x - 1)];
            let right = luma[y * dw + (x + 1)];
            let v_grad = (bot - top).abs();
            let h_grad = (right - left).abs();
            // Horizontal text/table rules have strong top/bottom transitions or sharp edges.
            let score = v_grad * 1.35 + h_grad * 0.35;
            if score > 22.0 {
                let clamped = score.min(220.0);
                points.push((x as f32 - cx, y as f32 - cy, clamped));
            }
        }
    }

    if points.len() < 24 {
        return 0.0;
    }

    let half_diag = ((dw as f32).hypot(dh as f32) * 0.55).ceil() + 4.0;
    let num_bins = (half_diag * 2.0) as usize + 4;

    // Pass 1: coarse sweep (-max_ang .. +max_ang step 0.5 deg)
    let mut best_alpha = 0.0f32;
    let mut best_energy = projection_energy(&points, 0.0, half_diag, num_bins);

    let steps = (max_ang / 0.5).ceil() as i32;
    for step in -steps..=steps {
        let a = (step as f32 * 0.5).clamp(-max_ang, max_ang);
        let e = projection_energy(&points, a, half_diag, num_bins);
        if e > best_energy {
            best_energy = e;
            best_alpha = a;
        }
    }

    // Pass 2: fine sweep around coarse winner (+-0.8 deg, step 0.15 deg)
    let center = best_alpha;
    for k in -6..=6 {
        let a = (center + k as f32 * 0.15).clamp(-max_ang, max_ang);
        let e = projection_energy(&points, a, half_diag, num_bins);
        if e > best_energy {
            best_energy = e;
            best_alpha = a;
        }
    }

    let correction = (-best_alpha).clamp(-max_ang, max_ang);
    if correction.abs() < 0.25 {
        0.0
    } else {
        (correction * 10.0).round() / 10.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn synthetic_tilted_lines(tilt_deg: f32) -> (Vec<i32>, usize, usize) {
        let w = 180usize;
        let h = 180usize;
        let rad = (tilt_deg as f64) * std::f64::consts::PI / 180.0;
        let cos_t = rad.cos() as f32;
        let sin_t = rad.sin() as f32;
        let cx = w as f32 * 0.5;
        let cy = h as f32 * 0.5;

        let mut buf = vec![0xFFF8F8F8u32 as i32; w * h];
        for y in 0..h {
            for x in 0..w {
                let dx = x as f32 - cx;
                let dy = y as f32 - cy;
                // Unrotate back into horizontal text-space
                let ux = dx * cos_t + dy * sin_t;
                let uy = -dx * sin_t + dy * cos_t;
                if ux.abs() < 60.0 && uy.abs() < 58.0 {
                    // Alternating crisp text bars spaced every 14px vertically, with word gaps
                    let bar_phase = (uy + 60.0).rem_euclid(14.0);
                    let word_gap = (ux + 60.0).rem_euclid(19.0);
                    if bar_phase < 5.0 && word_gap < 15.0 {
                        buf[y * w + x] = 0xFF181818u32 as i32;
                    }
                }
            }
        }
        (buf, w, h)
    }

    #[test]
    fn detects_clockwise_and_counterclockwise_text_skew() {
        let (cw_img, w, h) = synthetic_tilted_lines(6.0);
        let corr_cw = estimate_skew_correction_degrees(&cw_img, w, h, 15.0);
        assert!(
            (corr_cw - (-6.0)).abs() <= 0.6,
            "expected ~ -6.0 deg correction for +6 deg clockwise tilt, got {corr_cw}"
        );

        let (ccw_img, w2, h2) = synthetic_tilted_lines(-7.5);
        let corr_ccw = estimate_skew_correction_degrees(&ccw_img, w2, h2, 15.0);
        assert!(
            (corr_ccw - 7.5).abs() <= 0.6,
            "expected ~ +7.5 deg correction for -7.5 deg ccw tilt, got {corr_ccw}"
        );
    }

    #[test]
    fn blank_page_returns_zero() {
        let blank = vec![0xFFFFFFFFu32 as i32; 64 * 64];
        assert_eq!(estimate_skew_correction_degrees(&blank, 64, 64, 15.0), 0.0);
    }
}
