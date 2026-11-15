use std::cmp::Ordering;

/// Fast natural episode order comparator (`Tap 1`, `Tap 2`, `Tap 10`).
pub fn natural_compare(a: &str, b: &str) -> Ordering {
    let ba = a.as_bytes();
    let bb = b.as_bytes();
    let mut ia = 0usize;
    let mut ib = 0usize;

    while ia < ba.len() && ib < bb.len() {
        let ca = ba[ia];
        let cb = bb[ib];

        if ca.is_ascii_digit() && cb.is_ascii_digit() {
            let start_a = ia;
            while ia < ba.len() && ba[ia].is_ascii_digit() {
                ia += 1;
            }
            let start_b = ib;
            while ib < bb.len() && bb[ib].is_ascii_digit() {
                ib += 1;
            }

            let slice_a = trim_leading_zeros(&ba[start_a..ia]);
            let slice_b = trim_leading_zeros(&bb[start_b..ib]);

            match slice_a.len().cmp(&slice_b.len()) {
                Ordering::Equal => {}
                ord => return ord,
            }
            match slice_a.cmp(slice_b) {
                Ordering::Equal => {}
                ord => return ord,
            }
            // Prefer fewer leading zeros if numerically equal (e.g. "1" < "01")
            let raw_len_cmp = (ia - start_a).cmp(&(ib - start_b));
            if raw_len_cmp != Ordering::Equal {
                return raw_len_cmp;
            }
        } else {
            let la = ca.to_ascii_lowercase();
            let lb = cb.to_ascii_lowercase();
            if la != lb {
                return la.cmp(&lb);
            }
            ia += 1;
            ib += 1;
        }
    }

    ba.len().cmp(&bb.len())
}

fn trim_leading_zeros(digits: &[u8]) -> &[u8] {
    let mut idx = 0;
    while idx < digits.len() && digits[idx] == b'0' {
        idx += 1;
    }
    &digits[idx..]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn natural_episode_sorting() {
        let mut list = vec!["Tap 10.mp3", "Tap 2.mp3", "Tap 1.mp3", "Tap 20.mp3"];
        list.sort_by(|a, b| natural_compare(a, b));
        assert_eq!(list, vec!["Tap 1.mp3", "Tap 2.mp3", "Tap 10.mp3", "Tap 20.mp3"]);
    }
}
