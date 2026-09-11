import CoreServices
import Foundation

private final class TestSuite {
    private(set) var assertions = 0
    private(set) var failures = 0

    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        expect(actual == expected, "\(message) — expected \(expected), got \(actual)")
    }
}

private func testRecoveryActions(_ suite: TestSuite) {
    let ordinaryFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile
    )
    suite.expectEqual(
        FSEventsRecoveryPolicy.action(for: ordinaryFlags),
        .refreshSnapshot,
        "Ordinary item evidence should refresh the snapshot"
    )
    suite.expectEqual(
        FSEventsRecoveryPolicy.action(for: 0),
        .refreshSnapshot,
        "An event without recovery flags should refresh the snapshot"
    )

    let rebuildFlags: [(FSEventStreamEventFlags, String)] = [
        (FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs), "MustScanSubDirs"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped), "UserDropped"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped), "KernelDropped"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped), "EventIdsWrapped"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged), "RootChanged"),
    ]

    for (flag, name) in rebuildFlags {
        suite.expectEqual(
            FSEventsRecoveryPolicy.action(for: flag),
            .rebuildObservation,
            "\(name) should rebuild observation"
        )
        suite.expect(
            decodeFSEventFlags(flag).contains(name),
            "Existing FSEvents record decoding should expose \(name)"
        )
    }

    let combined = ordinaryFlags
        | FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
    suite.expectEqual(
        FSEventsRecoveryPolicy.action(for: combined),
        .rebuildObservation,
        "Recovery evidence should take precedence over ordinary item flags"
    )
}

private func testRootIdentity(_ suite: TestSuite) {
    let expected = ObservedRootIdentity(device: 1, inode: 10)
    suite.expectEqual(
        FSEventsRecoveryPolicy.rootDecision(expected: expected, current: expected),
        .restartAndEnumerate,
        "An unchanged root identity should restart and enumerate"
    )
    suite.expectEqual(
        FSEventsRecoveryPolicy.rootDecision(expected: expected, current: nil),
        .folderMissing,
        "A missing root should not be silently recovered"
    )
    suite.expectEqual(
        FSEventsRecoveryPolicy.rootDecision(
            expected: expected,
            current: ObservedRootIdentity(device: 1, inode: 11)
        ),
        .folderReplaced,
        "A different inode at the same path should require explicit re-mapping"
    )
    suite.expectEqual(
        FSEventsRecoveryPolicy.rootDecision(
            expected: expected,
            current: ObservedRootIdentity(device: 2, inode: 10)
        ),
        .folderReplaced,
        "A different device at the same path should require explicit re-mapping"
    )
}

private func run() -> Int32 {
    let suite = TestSuite()
    testRecoveryActions(suite)
    testRootIdentity(suite)
    print("Assertions: \(suite.assertions)")
    print("Failures: \(suite.failures)")
    return suite.failures == 0 ? 0 : 1
}

exit(run())
