// FSEventsFolderObserver.swift — Phase 0.5B FSEvents directory observer

import CoreServices
import Darwin
import Dispatch
import Foundation

final class ContextLifetimeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var creationCount = 0
    private var destructionCount = 0

    func recordCreation() {
        lock.withLock { creationCount += 1 }
    }

    func recordDestruction() {
        lock.withLock { destructionCount += 1 }
    }

    func snapshot() -> (created: Int, destroyed: Int) {
        lock.withLock { (creationCount, destructionCount) }
    }

    func reset() {
        lock.withLock {
            creationCount = 0
            destructionCount = 0
        }
    }
}

fileprivate final class ObserverWeakReference: @unchecked Sendable {
    private let lock = NSLock()
    private weak var value: FSEventsFolderObserver?

    init(_ value: FSEventsFolderObserver? = nil) {
        self.value = value
    }

    static func placeholder() -> ObserverWeakReference {
        ObserverWeakReference()
    }

    func install(_ value: FSEventsFolderObserver) {
        lock.withLock { self.value = value }
    }

    func withValue(_ body: (FSEventsFolderObserver) -> Void) {
        let snapshot = lock.withLock { value }
        if let snapshot {
            body(snapshot)
        }
    }
}

final class CallbackContext: @unchecked Sendable {
    static let lifetimeCounter = ContextLifetimeCounter()

    fileprivate let owner: ObserverWeakReference
    let registrationIdentity: UUID
    let generation: UInt64

    init(
        observer: FSEventsFolderObserver,
        registrationIdentity: UUID,
        generation: UInt64
    ) {
        owner = ObserverWeakReference(observer)
        self.registrationIdentity = registrationIdentity
        self.generation = generation
        Self.lifetimeCounter.recordCreation()
    }

    deinit {
        Self.lifetimeCounter.recordDestruction()
    }
}

private final class CallbackContextLease: @unchecked Sendable {
    private let lock = NSLock()
    private let pointer: UnsafeMutableRawPointer
    private var isReleased = false

    init(context: CallbackContext) {
        pointer = Unmanaged.passRetained(context).toOpaque()
    }

    var info: UnsafeMutableRawPointer {
        pointer
    }

    func releaseOnce() {
        let shouldRelease = lock.withLock {
            guard !isReleased else { return false }
            isReleased = true
            return true
        }
        if shouldRelease {
            Unmanaged<CallbackContext>.fromOpaque(pointer).release()
        }
    }

    deinit {
        releaseOnce()
    }
}

enum FSEventObserverState: Equatable, Sendable {
    case idle
    case running
    case stopping
    case stopped
}

private final class FSEventsRegistration: @unchecked Sendable {
    let identity: UUID
    let generation: UInt64

    private let lock = NSLock()
    private let completion = DispatchGroup()
    private let stream: FSEventStreamRef
    private let contextLease: CallbackContextLease
    private var isScheduled = false

    init(
        identity: UUID,
        generation: UInt64,
        stream: FSEventStreamRef,
        contextLease: CallbackContextLease
    ) {
        self.identity = identity
        self.generation = generation
        self.stream = stream
        self.contextLease = contextLease
        completion.enter()
    }

    func scheduleTeardown(
        on queue: DispatchQueue,
        owner: ObserverWeakReference
    ) {
        let shouldSchedule = lock.withLock {
            guard !isScheduled else { return false }
            isScheduled = true
            return true
        }
        guard shouldSchedule else { return }

        queue.async { [self, owner] in
            performTeardown(owner: owner)
        }
    }

    func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        completion.wait(timeout: timeout)
    }

    private func performTeardown(owner: ObserverWeakReference) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        contextLease.releaseOnce()
        owner.withValue { observer in
            observer.finishTeardown(registrationIdentity: identity)
        }
        completion.leave()
    }
}

/// A one-shot FSEvents observer with an explicit asynchronous teardown boundary.
///
/// The unchecked Sendable conformance is confined to this class. Mutable state
/// is lock-protected, the callback is immutable, and the public C callback is
/// isolated to the private serial lifecycle queue.
final class FSEventsFolderObserver: @unchecked Sendable {
    static let candidateLatency: CFTimeInterval = 0.3

    private let lock = NSLock()
    private let lifecycleQueue: DispatchQueue
    private let lifecycleQueueKey = DispatchSpecificKey<UInt8>()
    private let onEvent: @Sendable (FSEventRecord) -> Void
    private let weakOwner: ObserverWeakReference

    private var state: FSEventObserverState = .idle
    private var registration: FSEventsRegistration?
    private var generation: UInt64 = 0
    private var callbackBridgeFailures = 0

    init(
        queueLabel: String = "com.alcove.spike.fsevents-observer",
        onEvent: @escaping @Sendable (FSEventRecord) -> Void
    ) {
        lifecycleQueue = DispatchQueue(label: queueLabel)
        self.onEvent = onEvent
        weakOwner = ObserverWeakReference.placeholder()
        lifecycleQueue.setSpecific(key: lifecycleQueueKey, value: 1)
        weakOwner.install(self)
    }

    var lifecycleState: FSEventObserverState {
        lock.withLock { state }
    }

    var currentGeneration: UInt64 {
        lock.withLock { generation }
    }

    var currentRegistrationIdentity: UUID? {
        lock.withLock { registration?.identity }
    }

    var bridgeFailureCount: Int {
        lock.withLock { callbackBridgeFailures }
    }

    func start(path: String) throws {
        try lock.withLock {
            switch state {
            case .idle:
                break
            case .running:
                throw FSEventError.alreadyRunning
            case .stopping, .stopped:
                throw FSEventError.stopped
            }

            try Self.validateDirectory(path: path)
            let nextGeneration = generation &+ 1
            let nextIdentity = UUID()
            let context = CallbackContext(
                observer: self,
                registrationIdentity: nextIdentity,
                generation: nextGeneration
            )
            let contextLease = CallbackContextLease(context: context)
            var contextStruct = FSEventStreamContext(
                version: 0,
                info: contextLease.info,
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let paths = [path as CFString] as CFArray
            guard let stream = FSEventStreamCreate(
                nil,
                fsEventsCallback,
                &contextStruct,
                paths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                Self.candidateLatency,
                FSEventStreamCreateFlags(
                    kFSEventStreamCreateFlagUseCFTypes
                        | kFSEventStreamCreateFlagFileEvents
                        | kFSEventStreamCreateFlagWatchRoot
                )
            ) else {
                contextLease.releaseOnce()
                throw FSEventError.streamCreationFailed(path: path)
            }

            FSEventStreamSetDispatchQueue(stream, lifecycleQueue)
            guard FSEventStreamStart(stream) else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                contextLease.releaseOnce()
                throw FSEventError.streamStartFailed
            }

            generation = nextGeneration
            registration = FSEventsRegistration(
                identity: nextIdentity,
                generation: nextGeneration,
                stream: stream,
                contextLease: contextLease
            )
            state = .running
        }
    }

    /// Invalidates event acceptance and schedules stream teardown after all C
    /// callbacks already queued on the lifecycle queue. Safe from a callback.
    func stop() {
        let registrationToStop: FSEventsRegistration? = lock.withLock {
            switch state {
            case .idle:
                state = .stopped
                return nil
            case .running:
                state = .stopping
                return registration
            case .stopping, .stopped:
                return nil
            }
        }
        registrationToStop?.scheduleTeardown(on: lifecycleQueue, owner: weakOwner)
    }

    func waitUntilStopped(timeout: DispatchTime) throws {
        guard DispatchQueue.getSpecific(key: lifecycleQueueKey) == nil else {
            throw FSEventError.teardownWaitOnLifecycleQueue
        }
        let snapshot: (FSEventObserverState, FSEventsRegistration?) = lock.withLock {
            (state, registration)
        }
        switch snapshot.0 {
        case .idle, .running:
            throw FSEventError.teardownNotRequested
        case .stopping:
            break
        case .stopped:
            if snapshot.1 == nil { return }
        }
        guard let registration = snapshot.1 else { return }
        guard registration.wait(timeout: timeout) == .success else {
            throw FSEventError.teardownTimedOut
        }
    }

    @discardableResult
    func stopAndWait(timeout: DispatchTime) throws -> FSEventObserverState {
        stop()
        try waitUntilStopped(timeout: timeout)
        return lifecycleState
    }

    static func monotonicNow() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    fileprivate func deliver(
        path: String,
        eventID: FSEventStreamEventId,
        flags: FSEventStreamEventFlags,
        registrationIdentity deliveredIdentity: UUID,
        generation deliveredGeneration: UInt64,
        callbackBatchIdentity: UUID
    ) {
        let shouldDeliver = lock.withLock {
            state == .running
                && registration?.identity == deliveredIdentity
                && registration?.generation == deliveredGeneration
        }
        guard shouldDeliver else { return }
        onEvent(
            FSEventRecord(
                path: path,
                eventID: eventID,
                rawFlags: flags,
                decodedFlags: decodeFSEventFlags(flags),
                timestamp: Self.monotonicNow(),
                registrationIdentity: deliveredIdentity,
                generation: deliveredGeneration,
                callbackBatchIdentity: callbackBatchIdentity
            )
        )
    }

    fileprivate func recordCallbackBridgeFailure() {
        lock.withLock { callbackBridgeFailures += 1 }
    }

    fileprivate func finishTeardown(registrationIdentity: UUID) {
        lock.withLock {
            guard registration?.identity == registrationIdentity else { return }
            state = .stopped
        }
    }

    private static func validateDirectory(path: String) throws {
        let descriptor = Darwin.open(path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            let capturedError = errno
            if capturedError == ENOENT || capturedError == ENOTDIR {
                throw FSEventError.pathNotFound(path: path, code: capturedError)
            }
            throw FSEventError.openFailed(path: path, code: capturedError)
        }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            let capturedError = errno
            _ = Darwin.close(descriptor)
            throw FSEventError.metadataFailed(path: path, code: capturedError)
        }
        guard (metadata.st_mode & S_IFMT) == S_IFDIR else {
            _ = Darwin.close(descriptor)
            throw FSEventError.notADirectory(path: path)
        }
        guard Darwin.close(descriptor) == 0 else {
            throw FSEventError.validationDescriptorCloseFailed(errno)
        }
    }

    deinit {
        stop()
    }
}

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIDs: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let context = Unmanaged<CallbackContext>
        .fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    let batchIdentity = UUID()

    context.owner.withValue { observer in
        guard CFArrayGetCount(paths) == numEvents else {
            observer.recordCallbackBridgeFailure()
            return
        }
        for index in 0..<numEvents {
            guard let pathValue = CFArrayGetValueAtIndex(paths, index) else {
                observer.recordCallbackBridgeFailure()
                continue
            }
            let pathObject = Unmanaged<CFString>
                .fromOpaque(pathValue)
                .takeUnretainedValue()
            observer.deliver(
                path: pathObject as String,
                eventID: eventIDs[index],
                flags: eventFlags[index],
                registrationIdentity: context.registrationIdentity,
                generation: context.generation,
                callbackBatchIdentity: batchIdentity
            )
        }
    }
}
