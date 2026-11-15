//! Bilinear 4-corner perspective warp (planar homography) for document flattening on 0xAARRGGBB buffers.

#[inline]
fn clamp_norm(v: f32) -> f32 {
    if v.is_nan() {
        0.0
    } else {
        v.clamp(0.0, 1.0)
    }
}

#[inline]
fn norm_quad_to_pixels(src_w: usize, src_h: usize, q: &[f32; 8]) -> [(f32, f32); 4] {
    let max_x = (src_w.saturating_sub(1)) as f32;
    let max_y = (src_h.saturating_sub(1)) as f32;
    [
        (clamp_norm(q[0]) * max_x, clamp_norm(q[1]) * max_y),
        (clamp_norm(q[2]) * max_x, clamp_norm(q[3]) * max_y),
        (clamp_norm(q[4]) * max_x, clamp_norm(q[5]) * max_y),
        (clamp_norm(q[6]) * max_x, clamp_norm(q[7]) * max_y),
    ]
}

#[inline]
fn dist(a: (f32, f32), b: (f32, f32)) -> f32 {
    let dx = a.0 - b.0;
    let dy = a.1 - b.1;
    (dx * dx + dy * dy).sqrt()
}

pub fn estimate_quad_output_size(
    src_w: usize,
    src_h: usize,
    quad_norm: &[f32; 8],
    max_edge: usize,
) -> (usize, usize) {
    if src_w < 2 || src_h < 2 {
        return (src_w.max(16), src_h.max(16));
    }
    let pts = norm_quad_to_pixels(src_w, src_h, quad_norm);
    let top_w = dist(pts[0], pts[1]);
    let bot_w = dist(pts[3], pts[2]);
    let left_h = dist(pts[0], pts[3]);
    let right_h = dist(pts[1], pts[2]);

    let mut w = top_w.max(bot_w).round().max(16.0);
    let mut h = left_h.max(right_h).round().max(16.0);

    if max_edge >= 16 {
        let longest = w.max(h);
        if longest > max_edge as f32 {
            let scale = max_edge as f32 / longest;
            w = (w * scale).round().max(16.0);
            h = (h * scale).round().max(16.0);
        }
    }
    (w as usize, h as usize)
}

/// Solves 8x8 linear system `A * x = b` via Gaussian elimination with partial pivoting.
fn solve_8x8(mut a: [[f64; 9]; 8]) -> Option<[f64; 8]> {
    for col in 0..8 {
        let mut pivot_row = col;
        let mut best = a[col][col].abs();
        for r in (col + 1)..8 {
            let v = a[r][col].abs();
            if v > best {
                best = v;
                pivot_row = r;
            }
        }
        if best < 1e-9 {
            return None;
        }
        if pivot_row != col {
            a.swap(col, pivot_row);
        }
        let inv = 1.0 / a[col][col];
        for j in col..9 {
            a[col][j] *= inv;
        }
        for r in 0..8 {
            if r == col {
                continue;
            }
            let factor = a[r][col];
            if factor != 0.0 {
                for j in col..9 {
                    a[r][j] -= factor * a[col][j];
                }
            }
        }
    }
    let mut out = [0.0f64; 8];
    for i in 0..8 {
        out[i] = a[i][8];
    }
    Some(out)
}

/// Computes 3x3 homography mapping destination rectangle `[0..dst_w-1] x [0..dst_h-1]`
/// back to source coordinates defined by `[TL, TR, BR, BL]`.
fn compute_dst_to_src_homography(
    pts: [(f32, f32); 4],
    dst_w: usize,
    dst_h: usize,
) -> Option<[f64; 9]> {
    if dst_w < 2 || dst_h < 2 {
        return None;
    }
    let dw = (dst_w - 1) as f64;
    let dh = (dst_h - 1) as f64;
    let dst_pts = [(0.0, 0.0), (dw, 0.0), (dw, dh), (0.0, dh)];

    let mut mat = [[0.0f64; 9]; 8];
    for i in 0..4 {
        let (x, y) = dst_pts[i];
        let u = pts[i].0 as f64;
        let v = pts[i].1 as f64;

        let r0 = i * 2;
        mat[r0][0] = x;
        mat[r0][1] = y;
        mat[r0][2] = 1.0;
        mat[r0][6] = -u * x;
        mat[r0][7] = -u * y;
        mat[r0][8] = u;

        let r1 = r0 + 1;
        mat[r1][3] = x;
        mat[r1][4] = y;
        mat[r1][5] = 1.0;
        mat[r1][6] = -v * x;
        mat[r1][7] = -v * y;
        mat[r1][8] = v;
    }

    let c = solve_8x8(mat)?;
    Some([c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], 1.0])
}

#[inline]
fn sample_bilinear_argb(src: &[i32], w: usize, h: usize, sx: f32, sy: f32) -> i32 {
    let max_x = (w - 1) as f32;
    let max_y = (h - 1) as f32;
    let cx = sx.clamp(0.0, max_x);
    let cy = sy.clamp(0.0, max_y);

    let x0 = cx.floor() as usize;
    let y0 = cy.floor() as usize;
    let x1 = (x0 + 1).min(w - 1);
    let y1 = (y0 + 1).min(h - 1);

    let fx = cx - x0 as f32;
    let fy = cy - y0 as f32;
    let w00 = (1.0 - fx) * (1.0 - fy);
    let w10 = fx * (1.0 - fy);
    let w01 = (1.0 - fx) * fy;
    let w11 = fx * fy;

    let p00 = src[y0 * w + x0];
    let p10 = src[y0 * w + x1];
    let p01 = src[y1 * w + x0];
    let p11 = src[y1 * w + x1];

    let r = (((p00 >> 16) & 0xFF) as f32 * w00
        + ((p10 >> 16) & 0xFF) as f32 * w10
        + ((p01 >> 16) & 0xFF) as f32 * w01
        + ((p11 >> 16) & 0xFF) as f32 * w11)
        .round()
        .clamp(0.0, 255.0) as i32;
    let g = (((p00 >> 8) & 0xFF) as f32 * w00
        + ((p10 >> 8) & 0xFF) as f32 * w10
        + ((p01 >> 8) & 0xFF) as f32 * w01
        + ((p11 >> 8) & 0xFF) as f32 * w11)
        .round()
        .clamp(0.0, 255.0) as i32;
    let b = ((p00 & 0xFF) as f32 * w00
        + (p10 & 0xFF) as f32 * w10
        + (p01 & 0xFF) as f32 * w01
        + (p11 & 0xFF) as f32 * w11)
        .round()
        .clamp(0.0, 255.0) as i32;

    (0xFF << 24) | (r << 16) | (g << 8) | b
}

pub fn perspective_warp_into(
    src: &[i32],
    src_w: usize,
    src_h: usize,
    quad_norm: &[f32; 8],
    dst: &mut [i32],
    dst_w: usize,
    dst_h: usize,
) -> bool {
    let Some(src_total) = src_w.checked_mul(src_h) else {
        return false;
    };
    let Some(dst_total) = dst_w.checked_mul(dst_h) else {
        return false;
    };
    if src_w < 2 || src_h < 2 || dst_w < 2 || dst_h < 2 {
        return false;
    }
    if src.len() < src_total || dst.len() < dst_total {
        return false;
    }

    let pts = norm_quad_to_pixels(src_w, src_h, quad_norm);
    let Some(h) = compute_dst_to_src_homography(pts, dst_w, dst_h) else {
        return false;
    };

    for dy in 0..dst_h {
        let yf = dy as f64;
        let row_off = dy * dst_w;
        for dx in 0..dst_w {
            let xf = dx as f64;
            let denom = h[6] * xf + h[7] * yf + h[8];
            if denom.abs() < 1e-8 {
                dst[row_off + dx] = -1; // white fallback
                continue;
            }
            let sx = ((h[0] * xf + h[1] * yf + h[2]) / denom) as f32;
            let sy = ((h[3] * xf + h[4] * yf + h[5]) / denom) as f32;
            dst[row_off + dx] = sample_bilinear_argb(src, src_w, src_h, sx, sy);
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_quad_preserves_image() {
        let w = 8usize;
        let h = 6usize;
        let mut src = Vec::with_capacity(w * h);
        for y in 0..h {
            for x in 0..w {
                let r = (x * 30) as i32;
                let g = (y * 40) as i32;
                src.push((0xFF << 24) | (r << 16) | (g << 8) | 90);
            }
        }
        let mut dst = vec![0i32; w * h];
        let quad = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
        assert!(perspective_warp_into(&src, w, h, &quad, &mut dst, w, h));
        assert_eq!(dst, src);
    }

    #[test]
    fn trapezoid_quad_flattens_inner_region() {
        let w = 40usize;
        let h = 40usize;
        let mut src = vec![0xFF101010u32 as i32; w * h];
        // Paint bright red quad region in middle [10..30]
        for y in 10..=30 {
            for x in 10..=30 {
                src[y * w + x] = 0xFFE62222u32 as i32;
            }
        }
        let quad = [0.30, 0.30, 0.70, 0.30, 0.72, 0.70, 0.28, 0.70];
        let (dw, dh) = estimate_quad_output_size(w, h, &quad, 200);
        assert!(dw >= 16 && dh >= 16);
        let mut dst = vec![0i32; dw * dh];
        assert!(perspective_warp_into(&src, w, h, &quad, &mut dst, dw, dh));
        let center = dst[(dh / 2) * dw + (dw / 2)];
        let r = (center >> 16) & 0xFF;
        let g = (center >> 8) & 0xFF;
        assert!(r > 200 && g < 60, "expected red interior, got {:#x}", center);
    }

    #[test]
    fn degenerate_collinear_quad_returns_false() {
        let src = vec![-1i32; 16];
        let mut dst = vec![0i32; 16];
        let quad = [0.0, 0.0, 0.5, 0.0, 1.0, 0.0, 0.2, 0.0];
        assert!(!perspective_warp_into(&src, 4, 4, &quad, &mut dst, 4, 4));
    }
}
