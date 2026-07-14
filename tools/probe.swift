import AVFoundation

// Inspects a recording: overall + per-track durations, codecs, dimensions/audio format, and
// a monotonic-timestamp check per track (§3.5 drift / §4.1 pause gates rely on these).

func seconds(_ time: CMTime) -> String {
    time.seconds.isFinite ? String(format: "%.2f", time.seconds) : "n/a"
}

func fourCC(_ subtype: FourCharCode) -> String {
    String(bytes: withUnsafeBytes(of: subtype.bigEndian, Array.init), encoding: .ascii) ?? "?"
}

/// Reads every track's samples in one pass (passthrough — no decode) and reports, per track, a
/// warning if any decode timestamp steps *backward*. DTS is the right invariant: it stays
/// non-decreasing even when an encoder reorders frames (B-frames make *presentation* timestamps
/// legitimately out of order in storage), and a pause gap keeps it moving forward too. Audio
/// carries no DTS, so it falls back to PTS. Only a strictly backward step is flagged — a
/// genuinely corrupt pause seam or reordered append — because encoders emit a benign
/// equal-timestamp edit at the very start (priming) and an invalid trailing packet.
func monotonicWarnings(asset: AVAsset, tracks: [AVAssetTrack]) -> [CMPersistentTrackID: String] {
    guard let reader = try? AVAssetReader(asset: asset) else { return [:] }
    struct State { var last = CMTime.negativeInfinity; var samples = 0; var violations = 0 }

    var outputs: [(id: CMPersistentTrackID, output: AVAssetReaderTrackOutput)] = []
    var state: [CMPersistentTrackID: State] = [:]
    for track in tracks {
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { continue }
        reader.add(output)
        outputs.append((track.trackID, output))
        state[track.trackID] = State()
    }
    guard reader.startReading() else { return [:] }

    var active = Set(outputs.map(\.id))
    while !active.isEmpty {
        for (id, output) in outputs where active.contains(id) {
            guard let sample = output.copyNextSampleBuffer() else { active.remove(id); continue }
            let dts = CMSampleBufferGetDecodeTimeStamp(sample)
            let stamp = dts.isNumeric ? dts : CMSampleBufferGetPresentationTimeStamp(sample)
            guard stamp.isNumeric, var entry = state[id] else { continue }
            entry.samples += 1
            if CMTimeCompare(stamp, entry.last) < 0 { entry.violations += 1 }
            entry.last = stamp
            state[id] = entry
        }
    }
    reader.cancelReading()

    return state.compactMapValues { entry in
        entry.violations > 0
            ? "non-monotonic timestamps: \(entry.violations) of \(entry.samples) samples step backward"
            : nil
    }
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
let sem = DispatchSemaphore(value: 0)
Task {
    // Always release the semaphore, even if a load throws (missing/corrupt file) — otherwise
    // the main thread blocks on sem.wait() forever instead of exiting with an error.
    defer { sem.signal() }
    guard FileManager.default.fileExists(atPath: url.path) else {
        print("probe: no such file: \(url.path)")
        return
    }
    let duration: CMTime
    let tracks: [AVAssetTrack]
    do {
        duration = try await asset.load(.duration)
        tracks = try await asset.load(.tracks)
    } catch {
        print("probe: couldn't read \(url.lastPathComponent) (unreadable or still being written): \(error.localizedDescription)")
        return
    }
    print("duration: \(seconds(duration))s")
    let warnings = monotonicWarnings(asset: asset, tracks: tracks)
    for track in tracks {
        let trackDuration = seconds(try await track.load(.timeRange).duration)
        let media = track.mediaType.rawValue
        if let desc = try await track.load(.formatDescriptions).first {
            let subtype = fourCC(CMFormatDescriptionGetMediaSubType(desc))
            if media == "vide" {
                let dims = CMVideoFormatDescriptionGetDimensions(desc)
                let fps = String(format: "%.1f", try await track.load(.nominalFrameRate))
                print("track \(track.trackID): video \(subtype) \(dims.width)x\(dims.height) @ \(fps)fps  dur \(trackDuration)s")
            } else if media == "soun" {
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)!.pointee
                print("track \(track.trackID): audio \(subtype) \(Int(asbd.mSampleRate))Hz \(asbd.mChannelsPerFrame)ch  dur \(trackDuration)s")
            } else {
                print("track \(track.trackID): \(media) \(subtype)  dur \(trackDuration)s")
            }
        } else {
            print("track \(track.trackID): \(media)  dur \(trackDuration)s")
        }
        if let warning = warnings[track.trackID] { print("    ⚠︎ \(warning)") }
    }
    sem.signal()
}
sem.wait()
