import Foundation
import UploadCore

/// The CLI's own sign-in, apart from the app's: a test harness must never disconnect the app.
private let tokenStore = FileTokenStore(url: FileTokenStore.standardURL(named: "youtube-sign-in-cli"))

private func megabytes(_ bytes: Int64) -> String {
    String(format: "%.1f MB", Double(bytes) / 1_000_000)
}

private func youTubeErrorMessage(_ error: Error) -> String {
    switch error {
    case GoogleClientCredentialsError.missing(let url):
        return "No YouTube credentials at \(url.path).\ndocs/03 (M40) has the setup steps."
    case GoogleClientCredentialsError.cannotRead(let url, let reason):
        return "Couldn't read the YouTube credentials at \(url.path): \(reason)"
    case GoogleClientCredentialsError.unreadable:
        return "The credentials file isn't the JSON Google's console downloads."
    case GoogleClientCredentialsError.notADesktopClient:
        return "Those credentials are for another client type. Create a Desktop app client."
    case GoogleSignInError.denied:
        return "Sign-in was cancelled in the browser. Nothing was saved."
    case GoogleSignInError.refused(let reason):
        return "Google ended the sign-in (\(reason)). Nothing was saved."
    case LoopbackError.timedOut:
        return "Nothing came back from the browser in 5 minutes. Nothing was saved."
    case LoopbackError.notListening:
        return "Couldn't listen for the sign-in on this Mac. Nothing was saved."
    case GoogleSignInError.stateMismatch, GoogleSignInError.malformedRedirect:
        return "The browser came back without a usable sign-in. Nothing was saved."
    case GoogleSignInError.scopeNotGranted:
        return "Google didn't grant the upload permission. Nothing was saved."
    case GoogleSignInError.malformedResponse:
        return "Google's answer couldn't be read. Nothing was saved."
    case GoogleSignInError.signInExpired, YouTubeError.notAuthorized:
        return "The sign-in has expired or was removed. Run `screenrec-cli youtube connect` again."
    case GoogleSignInError.rejected(let error, let description):
        return "Google refused the sign-in: \(description ?? error)"
    case YouTubeError.noChannel:
        return "This Google account has no YouTube channel. Create one at youtube.com, then try again."
    case YouTubeError.quotaExceeded:
        return "YouTube's daily upload limit for this project is used up. It resets at midnight Pacific."
    case YouTubeError.uploadLimitExceeded:
        return "This channel has reached YouTube's upload limit for now."
    case YouTubeError.apiNotEnabled:
        return "YouTube Data API v3 isn't enabled on the Google Cloud project."
    case YouTubeError.sessionExpired:
        return "YouTube dropped the upload session. Start the upload again."
    case YouTubeError.malformedResponse:
        return "YouTube's answer couldn't be read."
    case YouTubeError.unreadableFile:
        return "That isn't a readable, non-empty file."
    case YouTubeError.rejected(let status, let reason, let message):
        return "YouTube refused the upload (\(reason ?? String(status))): \(message ?? "no reason given")"
    default:
        return "Couldn't finish: \(error.localizedDescription)"
    }
}

/// `youtube connect | upload <file> | disconnect` — the YouTube upload, proven headlessly before
/// the app has any surface for it (M40-T1, ADR-011).
func runYouTube(_ args: [String]) async {
    guard let action = args.first else { die("youtube needs connect, upload or disconnect") }
    let rest = Array(args.dropFirst())
    do {
        switch action {
        case "connect": try await connect(rest)
        case "upload": try await upload(rest)
        case "disconnect": try await disconnect(rest)
        default: die("Unknown youtube action: \(action)")
        }
    } catch {
        die(youTubeErrorMessage(error), code: 70)
    }
}

private func connect(_ args: [String]) async throws {
    guard args.isEmpty else { die("youtube connect takes no arguments") }
    let credentials = try GoogleClientCredentials(contentsOf: GoogleClientCredentials.defaultURL)
    // Replacing a sign-in would leave the old one valid at Google with nothing here to revoke it.
    guard try tokenStore.load() == nil else {
        die("Already connected. Run `screenrec-cli youtube disconnect` first.", code: 70)
    }
    let token = try await GoogleSignIn.signIn(credentials: credentials) { url in
        print("Opening Google's sign-in in your browser…")
        try openInBrowser(url)
        print("Waiting for you to finish there. Ctrl-C cancels.")
    }
    try tokenStore.save(token)

    print("Connected. The sign-in is saved in ~/Library/Application Support/ScreenRec.")
    if let expiry = token.refreshTokenExpiry {
        let days = Int((expiry.timeIntervalSinceNow / 86_400).rounded())
        print("This Google project is in Testing, so the sign-in expires in \(days) days.")
    }
}

private func openInBrowser(_ url: URL) throws {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = [url.absoluteString]
    try open.run()
    open.waitUntilExit()
    guard open.terminationStatus == 0 else { die("Couldn't open the browser.", code: 70) }
}

private func upload(_ args: [String]) async throws {
    var positionals: [String] = []
    var title: String?
    var description = ""
    var privacy = VideoMetadata.Privacy.private
    var interruptAt: Double?

    var index = 0
    func value(after flag: String) -> String {
        index += 1
        guard index < args.count else { die("\(flag) needs a value") }
        return args[index]
    }
    while index < args.count {
        switch args[index] {
        case "--title": title = value(after: "--title")
        case "--description": description = value(after: "--description")
        case "--privacy":
            guard let parsed = VideoMetadata.Privacy(rawValue: value(after: "--privacy")) else {
                die("--privacy must be private, unlisted or public")
            }
            privacy = parsed
        case "--interrupt-at":
            guard let fraction = Double(value(after: "--interrupt-at")), fraction > 0, fraction < 1
            else { die("--interrupt-at must be between 0 and 1") }
            interruptAt = fraction
        case let flag where flag.hasPrefix("--"): die("Unknown youtube upload option: \(flag)")
        default: positionals.append(args[index])
        }
        index += 1
    }
    guard let path = positionals.first else { die("youtube upload needs a file") }
    guard positionals.count == 1 else { die("Unexpected extra argument: \(positionals[1])") }
    let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let size: Int64
    do {
        size = try YouTubeUploader.fileSize(of: file)
    } catch {
        die("Nothing to upload at \(file.path). \(youTubeErrorMessage(error))")
    }

    let credentials = try GoogleClientCredentials(contentsOf: GoogleClientCredentials.defaultURL)
    guard var token = try tokenStore.load() else {
        die("Not connected. Run `screenrec-cli youtube connect` first.", code: 70)
    }
    let transport = URLSessionTransport()
    if token.needsRefresh() {
        do {
            token = try await GoogleSignIn.refresh(
                token, credentials: credentials, transport: transport)
        } catch GoogleSignInError.signInExpired {
            // A sign-in Google no longer honours is not one to keep offering.
            try tokenStore.delete()
            throw GoogleSignInError.signInExpired
        }
        try tokenStore.save(token)
    }

    let metadata = VideoMetadata(
        title: title ?? file.deletingPathExtension().lastPathComponent,
        description: description, privacy: privacy)
    let uploader = YouTubeUploader(transport: transport)
    let progress = ProgressPrinter(verb: "uploading")
    let report: @Sendable (Int64) -> Void = { progress.report(Double($0) / Double(size)) }

    print("Uploading \(file.lastPathComponent) (\(megabytes(size))) as \(privacy.rawValue)…")
    let started = Date()
    let video: UploadedVideo
    if let interruptAt {
        video = try await uploadInterrupted(
            file, at: interruptAt, of: size, metadata: metadata,
            accessToken: token.accessToken, uploader: uploader, report: report)
    } else {
        video = try await uploader.upload(
            file, metadata: metadata, accessToken: token.accessToken, progress: report)
    }
    progress.finish()

    let seconds = max(Date().timeIntervalSince(started), 0.001)
    print("Uploaded: \(video.link)")
    print(
        String(
            format: "  %@ · %@ · %.1f s at %.1f MB/s",
            video.title ?? metadata.title, video.privacyStatus ?? "visibility not returned",
            seconds, Double(size) / 1_000_000 / seconds))
    if let channel = video.channelTitle { print("  channel: \(channel)") }
    if video.uploadStatus == "uploaded" { print("  YouTube is still processing it.") }
}

/// Cuts its own transfer once `fraction` of the file has been sent, then asks YouTube how much it
/// holds and sends the rest — the resume path, exercised against the real server.
private func uploadInterrupted(
    _ file: URL, at fraction: Double, of size: Int64, metadata: VideoMetadata,
    accessToken: String, uploader: YouTubeUploader, report: @escaping @Sendable (Int64) -> Void
) async throws -> UploadedVideo {
    let session = try await uploader.openSession(
        for: file, metadata: metadata, accessToken: accessToken)
    let (reachedCut, cut) = AsyncStream<Void>.makeStream()
    let transfer = Task {
        try await uploader.send(file, to: session, accessToken: accessToken) { sent in
            report(sent)
            if Double(sent) >= fraction * Double(size) { cut.yield() }
        }
    }
    let cutter = Task {
        for await _ in reachedCut {
            transfer.cancel()
            return
        }
    }
    defer {
        cut.finish()
        cutter.cancel()
    }
    do {
        // Small enough to land before the cut: nothing was interrupted, and that is the result.
        return try await transfer.value
    } catch {
        guard transfer.isCancelled else { throw error }
    }

    let status = try await uploader.statusAfterBreak(of: session, accessToken: accessToken)
    switch status {
    case .complete:
        print("\n  cut the connection, but YouTube already had the whole file")
    case .incomplete(let nextOffset):
        print("\n  cut the connection; YouTube holds \(megabytes(nextOffset)) — resuming from there")
    }
    return try await uploader.resume(
        file, in: session, from: status, accessToken: accessToken, progress: report)
}

private func disconnect(_ args: [String]) async throws {
    guard args.isEmpty else { die("youtube disconnect takes no arguments") }
    guard let token = try tokenStore.load() else {
        print("Not connected. Nothing to do.")
        return
    }
    // Kept on any failure to revoke: deleting it would leave a live sign-in nothing here can end.
    do {
        try await GoogleSignIn.revoke(token, transport: URLSessionTransport())
    } catch is URLError {
        die("Couldn't reach Google, so the sign-in is still saved. Try again when you're online.", code: 70)
    } catch GoogleSignInError.rejected(let error, let description) {
        die("Google couldn't revoke the sign-in (\(description ?? error)), so it is still saved. Try again.", code: 70)
    }
    do {
        try tokenStore.delete()
    } catch {
        // The half that matters has happened; reporting only the failed delete would hide it.
        die(
            "Google has revoked the sign-in, but the saved copy couldn't be removed. "
                + youTubeErrorMessage(error),
            code: 70)
    }
    print("Disconnected. Google has revoked the sign-in and the saved copy is gone.")
}
