import CoreServices
import Darwin
import Dispatch
import Foundation

struct FolderRootIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

enum FolderObservationAction: Equatable {
    case refreshSnapshot
    case rebuildObservation
}

enum FolderObservationPolicy {
    private static let rebuildMask = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagEventIdsWrapped
            | kFSEventStreamEventFlagRootChanged
    )

    static func action(for flags: [FSEventStreamEventFlags]) -> FolderObservationAction {
        flags.contains { $0 & rebuildMask != 0 }
            ? .rebuildObservation
            : .refreshSnapshot
    }
}

enum FolderObservationError: Error, Equatable, Sendable {
    case streamCreationFailed(URL)
    case streamStartFailed(URL)
    case alreadyRunning
}

protocol FolderRootIdentifying: Sendable {
    func identity(for url: URL) async throws -> FolderRootIdentity
}

struct POSIXFolderRootIdentityProvider: FolderRootIdentifying {
    private static let queue = DispatchQueue(
        label: "com.dylanwang.alcove.folder-root-identity",
        qos: .userInitiated
    )

    func identity(for url: URL) async throws -> FolderRootIdentity {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<FolderRootIdentity, Error>) in
            Self.queue.async {
                var metadata = stat()
                guard Darwin.lstat(url.path, &metadata) == 0 else {
                    let error = NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(errno),
                        userInfo: [NSFilePathErrorKey: url.path]
                    )
                    continuation.resume(
                        throwing: FolderAccessError.classifyRootError(url: url, error: error)
                    )
                    return
                }
                continuation.resume(
                    returning: FolderRootIdentity(
                        device: UInt64(metadata.st_dev),
                        inode: UInt64(metadata.st_ino)
                    )
                )
            }
        }
    }
}

@MainActor
protocol FolderEventStreaming: AnyObject {
    func start(root: URL) throws
    func stop()
}

private final class FolderEventCallbackBox: Sendable {
    let handler: @Sendable ([FSEventStreamEventFlags]) -> Void

    init(handler: @escaping @Sendable ([FSEventStreamEventFlags]) -> Void) {
        self.handler = handler
    }
}

@MainActor
final class FSEventsFolderObserver: FolderEventStreaming {
    static let latency: CFTimeInterval = 0.3

    private let eventHandler: @MainActor ([FSEventStreamEventFlags]) -> Void
    private var stream: FSEventStreamRef?
    private var callbackBox: FolderEventCallbackBox?

    init(eventHandler: @escaping @MainActor ([FSEventStreamEventFlags]) -> Void) {
        self.eventHandler = eventHandler
    }

    func start(root: URL) throws {
        guard stream == nil else { throw FolderObservationError.alreadyRunning }

        let callbackBox = FolderEventCallbackBox { [weak self] flags in
            _ = Task { @MainActor [weak self] in
                self?.eventHandler(flags)
            }
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackBox).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [root.path as CFString] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
        )
        guard let stream = FSEventStreamCreate(
            nil,
            folderEventsCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            flags
        ) else {
            throw FolderObservationError.streamCreationFailed(root)
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw FolderObservationError.streamStartFailed(root)
        }

        self.callbackBox = callbackBox
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        callbackBox = nil
    }
}

private func folderEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIDs: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let callbackBox = Unmanaged<FolderEventCallbackBox>
        .fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()
    callbackBox.handler(Array(UnsafeBufferPointer(start: eventFlags, count: numEvents)))
}

@MainActor
final class FolderObservationCoordinator {
    typealias StreamFactory = @MainActor (
        @escaping @MainActor ([FSEventStreamEventFlags]) -> Void
    ) -> any FolderEventStreaming

    private let validator: FolderLocationValidator
    private let identityProvider: any FolderRootIdentifying
    private let streamFactory: StreamFactory
    private let debounceDuration: Duration
    private let onRefresh: @MainActor () -> Void
    private let onFailure: @MainActor (Error) -> Void
    private var stream: (any FolderEventStreaming)?
    private var root: URL?
    private var expectedIdentity: FolderRootIdentity?
    private var generation: UInt64 = 0
    private var debounceTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?

    init(
        validator: FolderLocationValidator = FolderLocationValidator(),
        identityProvider: any FolderRootIdentifying = POSIXFolderRootIdentityProvider(),
        streamFactory: @escaping StreamFactory = { handler in
            FSEventsFolderObserver(eventHandler: handler)
        },
        debounceDuration: Duration = .milliseconds(200),
        onRefresh: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) {
        self.validator = validator
        self.identityProvider = identityProvider
        self.streamFactory = streamFactory
        self.debounceDuration = debounceDuration
        self.onRefresh = onRefresh
        self.onFailure = onFailure
    }

    func start(root: URL) async throws {
        stop()
        generation += 1
        let startGeneration = generation
        let validatedRoot = try await validator.validate(root)
        let identity = try await identityProvider.identity(for: validatedRoot)
        guard !Task.isCancelled, startGeneration == generation else {
            throw CancellationError()
        }
        self.root = validatedRoot
        expectedIdentity = identity
        try installStream(root: validatedRoot, generation: startGeneration)
    }

    func stop() {
        generation += 1
        debounceTask?.cancel()
        recoveryTask?.cancel()
        debounceTask = nil
        recoveryTask = nil
        stream?.stop()
        stream = nil
        root = nil
        expectedIdentity = nil
    }

    func receive(flags: [FSEventStreamEventFlags]) {
        switch FolderObservationPolicy.action(for: flags) {
        case .refreshSnapshot:
            scheduleRefresh()
        case .rebuildObservation:
            rebuildObservation()
        }
    }

    private func installStream(root: URL, generation: UInt64) throws {
        let stream = streamFactory { [weak self] flags in
            guard let self, self.generation == generation else { return }
            self.receive(flags: flags)
        }
        try stream.start(root: root)
        self.stream = stream
    }

    private func scheduleRefresh() {
        let eventGeneration = generation
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounceDuration] in
            do {
                try await Task.sleep(for: debounceDuration)
            } catch {
                return
            }
            guard let self, self.generation == eventGeneration else { return }
            self.onRefresh()
        }
    }

    private func rebuildObservation() {
        guard let root, let expectedIdentity else { return }
        generation += 1
        let recoveryGeneration = generation
        debounceTask?.cancel()
        recoveryTask?.cancel()
        stream?.stop()
        stream = nil
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let validatedRoot = try await validator.validate(root)
                let currentIdentity = try await identityProvider.identity(for: validatedRoot)
                guard !Task.isCancelled, generation == recoveryGeneration else { return }
                guard currentIdentity == expectedIdentity else {
                    onFailure(FolderAccessError.folderReplaced(url: validatedRoot))
                    return
                }
                try installStream(root: validatedRoot, generation: recoveryGeneration)
                onRefresh()
            } catch is CancellationError {
                return
            } catch {
                guard generation == recoveryGeneration else { return }
                onFailure(error)
            }
        }
    }
}
