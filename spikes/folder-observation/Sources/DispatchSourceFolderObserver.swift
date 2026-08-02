// DispatchSourceFolderObserver.swift — Phase 0.5A DispatchSource directory observer

import Darwin
import Dispatch
import Foundation

struct ObservedFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct FolderObserverTeardown: Equatable, Sendable {
    let descriptorWasOpened: Bool
    let descriptorWasClosed: Bool
}

private final class DescriptorCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private let completion = DispatchGroup()
    private var descriptor: Int32
    private var closeError: Int32?
    private var isComplete = false

    init(descriptor: Int32) {
        self.descriptor = descriptor
        completion.enter()
    }

    var currentDescriptor: Int32 {
        lock.withLock { descriptor }
    }

    func finish(beforeSignal: @Sendable () -> Void) {
        let descriptorToClose: Int32? = lock.withLock {
            guard !isComplete else { return nil }
            isComplete = true
            let value = descriptor
            descriptor = -1
            return value
        }
        guard let descriptorToClose else { return }

        let result = Darwin.close(descriptorToClose)
        if result != 0 {
            let capturedError = errno
            lock.withLock { closeError = capturedError }
        }
        beforeSignal()
        completion.leave()
    }

    func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        completion.wait(timeout: timeout)
    }

    func teardownResult() throws -> FolderObserverTeardown {
        try lock.withLock {
            if let closeError {
                throw FolderObserverError.descriptorCloseFailed(closeError)
            }
            return FolderObserverTeardown(
                descriptorWasOpened: true,
                descriptorWasClosed: isComplete && descriptor == -1
            )
        }
    }

    deinit {
        let descriptorToClose: Int32? = lock.withLock {
            guard !isComplete else { return nil }
            isComplete = true
            let value = descriptor
            descriptor = -1
            return value
        }
        if let descriptorToClose {
            _ = Darwin.close(descriptorToClose)
            completion.leave()
        }
    }
}

private final class FolderObserverWeakReference: @unchecked Sendable {
    private let lock = NSLock()
    private weak var value: DispatchSourceFolderObserver?

    init(_ value: DispatchSourceFolderObserver) {
        self.value = value
    }

    func withValue(_ body: (DispatchSourceFolderObserver) -> Void) {
        let snapshot = lock.withLock { value }
        if let snapshot {
            body(snapshot)
        }
    }
}

/// A one-shot DispatchSource directory observer with lock-protected lifecycle state.
///
/// The unchecked Sendable conformance is confined to this class: every mutable
/// property is protected by `lock`, the callback is immutable, and source handlers
/// run on the private serial event queue. Call `stop()` to initiate cancellation,
/// then `waitUntilStopped(timeout:)` when deterministic teardown is required.
final class DispatchSourceFolderObserver: @unchecked Sendable {
    enum State: Equatable, Sendable {
        case idle
        case running
        case stopping
        case stopped
    }

    private let lock = NSCondition()
    private let eventQueue: DispatchQueue
    private let eventQueueKey = DispatchSpecificKey<UInt8>()
    private let onEvent: @Sendable (FolderObservationRecord) -> Void

    private var state: State = .idle
    private var source: DispatchSourceFileSystemObject?
    private var cancellation: DescriptorCancellation?
    private var registrationID: UUID?
    private var fileIdentity: ObservedFileIdentity?
    private var generation: UInt64 = 0
    private var activeDeliveries = 0

    init(
        queueLabel: String = "com.alcove.spike.folder-observer",
        onEvent: @escaping @Sendable (FolderObservationRecord) -> Void
    ) {
        eventQueue = DispatchQueue(label: queueLabel)
        self.onEvent = onEvent
        eventQueue.setSpecific(key: eventQueueKey, value: 1)
    }

    var lifecycleState: State {
        lock.withLock { state }
    }

    var currentGeneration: UInt64 {
        lock.withLock { generation }
    }

    var openedFileDescriptor: Int32 {
        lock.withLock { cancellation?.currentDescriptor ?? -1 }
    }

    var observedFileIdentity: ObservedFileIdentity? {
        lock.withLock { fileIdentity }
    }

    /// Opens and starts observing one existing directory.
    ///
    /// Setup is serialized under one lock so a concurrent stop cannot return in
    /// the middle of an uncommitted start and later leave the observer running.
    func start(path: String) throws {
        try lock.withLock {
            switch state {
            case .idle:
                break
            case .running:
                throw FolderObserverError.alreadyRunning
            case .stopping, .stopped:
                throw FolderObserverError.stopped
            }

            let openedDescriptor = Darwin.open(path, O_EVTONLY | O_CLOEXEC)
            guard openedDescriptor >= 0 else {
                throw FolderObserverError.openFailed(path: path, code: errno)
            }

            var metadata = stat()
            guard Darwin.fstat(openedDescriptor, &metadata) == 0 else {
                let capturedError = errno
                _ = Darwin.close(openedDescriptor)
                throw FolderObserverError.metadataFailed(path: path, code: capturedError)
            }
            guard (metadata.st_mode & S_IFMT) == S_IFDIR else {
                _ = Darwin.close(openedDescriptor)
                throw FolderObserverError.notADirectory(path)
            }

            let nextGeneration = generation &+ 1
            let nextRegistrationID = UUID()
            let nextCancellation = DescriptorCancellation(descriptor: openedDescriptor)
            let owner = FolderObserverWeakReference(self)
            let nextSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: openedDescriptor,
                eventMask: [.write, .rename, .delete, .revoke],
                queue: eventQueue
            )

            nextSource.setEventHandler { [weak self, weak nextSource] in
                guard let nextSource else { return }
                self?.deliver(
                    rawEventMask: nextSource.data.rawValue,
                    registrationID: nextRegistrationID,
                    generation: nextGeneration
                )
            }
            nextSource.setCancelHandler { [nextCancellation, owner] in
                nextCancellation.finish {
                    owner.withValue { observer in
                        observer.finishCancellation(
                            registrationID: nextRegistrationID,
                            cancellation: nextCancellation
                        )
                    }
                }
            }

            generation = nextGeneration
            registrationID = nextRegistrationID
            cancellation = nextCancellation
            fileIdentity = ObservedFileIdentity(
                device: UInt64(metadata.st_dev),
                inode: UInt64(metadata.st_ino)
            )
            source = nextSource
            state = .running
            nextSource.resume()
        }
    }

    /// Initiates cancellation. This method is idempotent and may be called from
    /// the event callback. It does not block the event queue.
    func stop() {
        lock.lock()
        switch state {
        case .idle:
            state = .stopped
        case .running:
            state = .stopping
            registrationID = nil
            source?.cancel()
            source = nil
        case .stopping, .stopped:
            break
        }

        // An external caller does not return while a user callback is active.
        // A callback may itself initiate stop, in which case waiting here would
        // wait on the current callback and deadlock.
        if DispatchQueue.getSpecific(key: eventQueueKey) == nil {
            while activeDeliveries > 0 {
                lock.wait()
            }
        }
        lock.unlock()
    }

    /// Waits for the cancel handler to close the descriptor and finish state
    /// teardown. Calling this from the event callback is rejected to avoid
    /// waiting on the queue that must execute the cancel handler.
    func waitUntilStopped(timeout: DispatchTime) throws -> FolderObserverTeardown {
        guard DispatchQueue.getSpecific(key: eventQueueKey) == nil else {
            throw FolderObserverError.teardownWaitOnEventQueue
        }

        let snapshot: (State, DescriptorCancellation?) = lock.withLock {
            (state, cancellation)
        }
        switch snapshot.0 {
        case .idle, .running:
            throw FolderObserverError.teardownNotRequested
        case .stopping:
            break
        case .stopped:
            if snapshot.1 == nil {
                return FolderObserverTeardown(
                    descriptorWasOpened: false,
                    descriptorWasClosed: false
                )
            }
        }

        guard let cancellation = snapshot.1 else {
            return FolderObserverTeardown(
                descriptorWasOpened: false,
                descriptorWasClosed: false
            )
        }
        guard cancellation.wait(timeout: timeout) == .success else {
            throw FolderObserverError.teardownTimedOut
        }
        return try cancellation.teardownResult()
    }

    @discardableResult
    func stopAndWait(timeout: DispatchTime) throws -> FolderObserverTeardown {
        stop()
        return try waitUntilStopped(timeout: timeout)
    }

    static func monotonicNow() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    private func deliver(
        rawEventMask: UInt,
        registrationID deliveredRegistrationID: UUID,
        generation deliveredGeneration: UInt64
    ) {
        lock.lock()
        guard state == .running,
              registrationID == deliveredRegistrationID,
              generation == deliveredGeneration
        else {
            lock.unlock()
            return
        }
        activeDeliveries += 1
        lock.unlock()

        defer {
            lock.lock()
            activeDeliveries -= 1
            lock.broadcast()
            lock.unlock()
        }
        onEvent(
            FolderObservationRecord(
                rawEventMask: rawEventMask,
                timestamp: Self.monotonicNow(),
                generation: deliveredGeneration
            )
        )
    }

    private func finishCancellation(
        registrationID finishedRegistrationID: UUID,
        cancellation finishedCancellation: DescriptorCancellation
    ) {
        lock.withLock {
            guard cancellation === finishedCancellation else { return }
            if registrationID == finishedRegistrationID {
                registrationID = nil
            }
            state = .stopped
        }
    }

    deinit {
        stop()
    }
}
