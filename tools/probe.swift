import AVFoundation

// Inspects a recording: overall + per-track durations, codecs, dimensions/audio format, and
// a monotonic-timestamp check per track (§3.5 drift / §4.1 pause gates rely on these).

func seconds(_ time: CMTime) -> String {
    time.seconds.isFinite ? String(format: "%.2f", time.seconds) : "n/a"
}

func fourCC(_ subtype: FourCharCode) -> String {
    String(bytes: withUnsafeBytes(of: subtype.bigEndian, Array.init), encoding: .ascii) ?? "?"
}

/// Reads every track's samples in one pass (passthrough — no decode) and warns, per track, if a
/// timestamp steps backward. Judges on DTS: HEVC B-frames make PTS legitimately non-monotonic in
/// storage, and our own capture emits them. The two clocks are never mixed — a track's first and
/// last few samples carry no DTS, and falling back to their PTS reads as a backward step on any
/// B-frame file. A track with no DTS at all is judged on PTS. Only strictly backward steps are
/// flagged: encoders emit a benign equal-timestamp priming edit.
func monotonicWarnings(asset: AVAsset, tracks: [AVAssetTrack]) -> [CMPersistentTrackID: String] {
    guard let reader = try? AVAssetReader(asset: asset) else { return [:] }
    struct Clock {
        var last = CMTime.negativeInfinity
        var samples = 0
        var violations = 0

        mutating func step(_ stamp: CMTime) {
            samples += 1
            if CMTimeCompare(stamp, last) < 0 { violations += 1 }
            last = stamp
        }
    }
    struct State { var decode = Clock(); var presentation = Clock() }

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
            guard var entry = state[id] else { continue }
            let dts = CMSampleBufferGetDecodeTimeStamp(sample)
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if dts.isNumeric { entry.decode.step(dts) }
            if pts.isNumeric { entry.presentation.step(pts) }
            state[id] = entry
        }
    }
    reader.cancelReading()

    return state.compactMapValues { entry in
        let clock = entry.decode.samples > 0 ? entry.decode : entry.presentation
        return clock.violations > 0
            ? "non-monotonic timestamps: \(clock.violations) of \(clock.samples) samples step backward"
            : nil
    }
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
let sem = DispatchSemaphore(value: 0)
Task {
    // Always release the semaphore: a throwing load would otherwise block sem.wait() forever.
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
