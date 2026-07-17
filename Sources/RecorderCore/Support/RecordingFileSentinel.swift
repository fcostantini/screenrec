import Foundation

/// Defends the in-progress recording file: watches it through a private `O_EVTONLY`
/// descriptor and reacts when something else moves or deletes it mid-recording.
///
/// A same-volume move (the Trash included) is renamed straight back — the writer's own fd
/// follows the inode, so the recording never notices either way. An unlink is fatal: the
/// bytes die with the descriptor, so the owner must fail-stop instead of writing on into a
/// doomed inode. A cross-volume "move" arrives as delete (copy + unlink), never as rename.
/// A value settable from any thread and read elsewhere without racing — for one-shot state
/// crossing from a callback queue to teardown code.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func set(_ value: Value) {
        lock.lock(); stored = value; lock.unlock()
    }
}

public final class RecordingFileSentinel: @unchecked Sendable {
    public enum Incident: Sendable, Equatable {
        /// Found at `from`, renamed back to the reserved path; recording unaffected.
        case movedAndRestored(from: String)
        /// Moved somewhere it couldn't be renamed back from; finalize can no longer find it.
        case movedAndUnrestorable(to: String)
        /// Unlinked. Unsalvageable — there is no macOS API to relink an open descriptor.
        case deleted
    }

    private let reservedPath: String
    private let onIncident: @Sendable (Incident) -> Void
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var cancelled = false

    private static let queue = DispatchQueue(
        label: "dev.fcostantini.screenrec.file-sentinel", qos: .utility)

    /// Nil when the file can't be opened — the caller records that and proceeds unguarded
    /// rather than failing a recording over its bodyguard.
    public init?(url: URL, onIncident: @escaping @Sendable (Incident) -> Void) {
        // Resolve with realpath(3): `F_GETPATH` reports fully resolved paths (/private/tmp/…),
        // and Foundation's resolvingSymlinksInPath goes the WRONG way for exactly those (it
        // strips /private) — a mismatch here makes every echo of our own rename-back look like
        // another move. Resolve the parent; the file itself may legitimately be mid-move.
        let parent = url.deletingLastPathComponent().path
        var resolvedParent = parent
        if let real = realpath(parent, nil) {
            resolvedParent = String(cString: real)
            free(real)
        }
        reservedPath = resolvedParent + "/" + url.lastPathComponent
        self.onIncident = onIncident
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.rename, .delete], queue: Self.queue)
        source.setEventHandler { [weak self] in self?.handleEvent() }
        source.setCancelHandler { close(descriptor) }
        // Under the lock: the handler reads `source` from its queue the moment activation
        // delivers a pending event, and queue activation is not a synchronization edge TSan
        // (or the memory model) recognizes against this write.
        lock.lock()
        self.source = source
        lock.unlock()
        source.activate()
    }

    deinit {
        cancel()
    }

    /// Stop watching. Safe to call more than once, including from the event handler itself.
    public func cancel() {
        lock.lock()
        cancelled = true
        let source = self.source
        self.source = nil
        lock.unlock()
        source?.cancel()
    }

    /// `cancel()`, then wait out any handler already past the cancelled-guard — the owner's own
    /// finalize rename must not race a rename-back still in flight. Never call from the event
    /// queue (the handler uses plain `cancel()`); the sync would deadlock.
    public func cancelAndWait() {
        cancel()
        Self.queue.sync {}
    }

    private func handleEvent() {
        lock.lock()
        guard !cancelled, let source else {
            lock.unlock()
            return
        }
        let data = source.data
        let descriptor = source.handle
        lock.unlock()

        if data.contains(.delete) {
            cancel()                      // the inode is gone; nothing left to watch
            onIncident(.deleted)
            return
        }
        guard data.contains(.rename) else { return }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard fcntl(Int32(descriptor), F_GETPATH, &buffer) == 0 else { return }
        let currentPath = String(cString: buffer)
        guard currentPath != reservedPath else { return }   // echo of our own rename-back
        if rename(currentPath, reservedPath) == 0 {
            onIncident(.movedAndRestored(from: currentPath))
        } else {
            cancel()
            onIncident(.movedAndUnrestorable(to: currentPath))
        }
    }
}
