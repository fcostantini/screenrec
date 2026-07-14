import AVFoundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
let sem = DispatchSemaphore(value: 0)
Task {
    let duration = try await asset.load(.duration)
    print("duration: \(String(format: "%.2f", duration.seconds))s")
    for track in try await asset.load(.tracks) {
        let desc = try await track.load(.formatDescriptions).first
        let media = track.mediaType.rawValue
        if let desc {
            let subtype = CMFormatDescriptionGetMediaSubType(desc)
            let fourcc = String(bytes: withUnsafeBytes(of: subtype.bigEndian, Array.init), encoding: .ascii) ?? "?"
            if media == "vide" {
                let dims = CMVideoFormatDescriptionGetDimensions(desc)
                print("track \(track.trackID): video \(fourcc) \(dims.width)x\(dims.height) @ \(String(format: "%.1f", try await track.load(.nominalFrameRate)))fps")
            } else if media == "soun" {
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)!.pointee
                print("track \(track.trackID): audio \(fourcc) \(Int(asbd.mSampleRate))Hz \(asbd.mChannelsPerFrame)ch")
            } else {
                print("track \(track.trackID): \(media) \(fourcc)")
            }
        }
    }
    sem.signal()
}
sem.wait()
