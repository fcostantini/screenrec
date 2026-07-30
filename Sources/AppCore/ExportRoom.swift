import Foundation
import RecorderCore

/// Whether a derived file fits on the volume it would be written to (M23-T2).
///
/// The capture side of this is `RecordingRoom` plus the fail-stop floor: a take is open-ended, so it
/// can only be stopped part-way. An export's length is known before it starts, so the honest shape is
/// the opposite one — refuse up front, and never write a byte that can't land.
public enum ExportRoom {

    /// Why an export wasn't started. Carries the two numbers the user needs to act.
    public struct Shortfall: Equatable, Sendable {
        public let needBytes: Int64
        public let freeBytes: Int64
        /// The volume's name, for the notice — the disk is the thing to go and fix.
        public let volumeName: String
    }

    /// Whether `needBytes` fits in `freeBytes`. Pure.
    ///
    /// No reserve is subtracted, unlike `RecordingRoom`: capture holds back 2 GB because it cannot
    /// know when to stop, while `needBytes` is already a ceiling for a bounded job (the rate budget
    /// over-quotes easy content several-fold, docs/07). Stacking a capture-sized reserve on top of a
    /// ceiling would refuse most exports on a healthy disk.
    ///
    /// A nil `needBytes` — no defensible estimate for this kind of export, e.g. a GIF — fits by
    /// definition: guessing would refuse exports that work and pass ones that don't.
    public static func fits(needBytes: Int64?, freeBytes: Int64?) -> Bool {
        guard let needBytes, let freeBytes else { return true }
        return needBytes <= freeBytes
    }

    /// The volume name to name in the notice, falling back to the path's last component — a
    /// volume with no readable name is still better identified than not at all.
    public static func volumeName(forPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName
        return name ?? url.lastPathComponent
    }
}
