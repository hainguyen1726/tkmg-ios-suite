import Foundation
import TkmgCore

enum RustBridge {
    /// Compares two strings in natural episode order ("Tap 2" < "Tap 10") via Rust ARM64 core.
    static func naturalCompare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let aBytes = Array(lhs.utf8)
        let bBytes = Array(rhs.utf8)
        let result: Int32 = aBytes.withUnsafeBufferPointer { aBuf in
            bBytes.withUnsafeBufferPointer { bBuf in
                tkmg_natural_compare_utf8(
                    aBuf.baseAddress,
                    aBuf.count,
                    bBuf.baseAddress,
                    bBuf.count
                )
            }
        }
        if result < 0 { return .orderedAscending }
        if result > 0 { return .orderedDescending }
        return .orderedSame
    }
}
