// ScreenObserver.swift
// Alcove Spike 0.2B — Notification observer for display parameter changes.
//
// Observes `NSApplication.didChangeScreenParametersNotification` with an
// owned NotificationCenter token. Start/stop are idempotent and callbacks
// are handed to MainActor before reading screen state.
// Disposable spike code, not production AlcoveCore.

import AppKit
import Foundation

/// Observes `NSApplication.didChangeScreenParametersNotification`.
///
/// Owns the notification registration and delivers fresh snapshots on
/// `MainActor`. Registration is synchronous, so `start()` has no race with a
/// notification posted immediately after it returns.
@MainActor
public final class ScreenObserver {
    public typealias SnapshotProvider = @MainActor () -> [ScreenRecord]
    public typealias EventHandler = @MainActor ([ScreenRecord]) -> Void

    private let center: NotificationCenter
    private let snapshotProvider: SnapshotProvider
    private let eventHandler: EventHandler
    private var observationToken: NotificationToken?
    private var generation: UInt64 = 0

    public var isObserving: Bool { observationToken != nil }

    public init(
        center: NotificationCenter = .default,
        snapshotProvider: @escaping SnapshotProvider = { ScreenInventory.capture() },
        eventHandler: @escaping EventHandler
    ) {
        self.center = center
        self.snapshotProvider = snapshotProvider
        self.eventHandler = eventHandler
    }

    public func start() {
        guard observationToken == nil else { return }
        generation += 1
        let registrationGeneration = generation
        let token = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      observationToken != nil,
                      generation == registrationGeneration else { return }
                eventHandler(snapshotProvider())
            }
        }
        observationToken = NotificationToken(token)
    }

    public func stop() {
        guard let observationToken else { return }
        center.removeObserver(observationToken.value)
        self.observationToken = nil
    }

    deinit {
        if let observationToken {
            center.removeObserver(observationToken.value)
        }
    }
}

/// Objective-C observer tokens are immutable identity objects but are not
/// annotated `Sendable`. This wrapper only transfers the token to `deinit`;
/// all registration and removal state remains MainActor-isolated.
private final class NotificationToken: @unchecked Sendable {
    let value: any NSObjectProtocol

    init(_ value: any NSObjectProtocol) {
        self.value = value
    }
}
