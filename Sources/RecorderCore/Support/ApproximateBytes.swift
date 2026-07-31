import Foundation

/// Byte counts a surface quotes from a model instead of measuring — the armed buffer's memory, an
/// export's weight per minute. Rounded to two significant figures, because `183,1 MB` reads as a
/// measurement and these are estimates.
public enum ApproximateBytes {

    /// `183_100_000` → `180 MB`, in the user's locale.
    public static func formatted(_ bytes: Int64) -> String {
        // Built per call rather than held as a static: `ByteCountFormatter` keeps internal state and
        // Apple has never documented it as safe for concurrent use, so `nonisolated(unsafe)` would
        // assert an invariant nobody can justify. This is menu-open copy, never the sample path.
        let formatter = ByteCountFormatter()
        // `.file` is decimal, which is what Finder shows the same file as.
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: roundedToTwoSignificantFigures(bytes))
    }

    static func roundedToTwoSignificantFigures(_ bytes: Int64) -> Int64 {
        guard bytes > 0 else { return 0 }
        let magnitude = pow(10, (log10(Double(bytes)).rounded(.down) - 1))
        guard magnitude >= 1 else { return bytes }
        return Int64(((Double(bytes) / magnitude).rounded() * magnitude).rounded())
    }
}
