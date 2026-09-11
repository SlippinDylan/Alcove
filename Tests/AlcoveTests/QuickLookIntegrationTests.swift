import AppKit
import Quartz
import XCTest
@testable import Alcove

final class QuickLookIntegrationTests: XCTestCase {
    @MainActor
    func testSelectionKeepsGridOrderForPreviewDataSource() {
        let panel = QuickLookPanelSpy()
        let integration = QuickLookIntegration(panelProvider: { panel })
        let urls = [
            URL(fileURLWithPath: "/tmp/first.pdf"),
            URL(fileURLWithPath: "/tmp/second.png"),
        ]

        integration.updateSelection(urls)

        XCTAssertEqual(integration.selectedURLs, urls)
        XCTAssertEqual(integration.numberOfPreviewItems(in: nil), 2)
        XCTAssertEqual(integration.previewPanel(nil, previewItemAt: 0).previewItemURL, urls[0])
        XCTAssertEqual(integration.previewPanel(nil, previewItemAt: 1).previewItemURL, urls[1])
    }

    @MainActor
    func testSpacePresentsSelectionThenDismissesOnlyTheOwnedPanel() {
        let panel = QuickLookPanelSpy()
        let integration = QuickLookIntegration(panelProvider: { panel })
        let url = URL(fileURLWithPath: "/tmp/preview.txt")

        integration.handleSpace(for: [url])

        XCTAssertEqual(panel.presentationCount, 1)
        XCTAssertTrue(panel.dataSource === integration)
        XCTAssertTrue(panel.delegate === integration)

        integration.handleSpace(for: [url])

        XCTAssertEqual(panel.dismissalCount, 1)
        XCTAssertNil(panel.dataSource)
        XCTAssertNil(panel.delegate)
    }

    @MainActor
    func testSpaceWithEmptySelectionDoesNotRequestPanel() {
        let panel = QuickLookPanelSpy()
        let integration = QuickLookIntegration(panelProvider: { panel })

        integration.handleSpace(for: [])

        XCTAssertEqual(panel.presentationCount, 0)
        XCTAssertNil(panel.dataSource)
        XCTAssertNil(panel.delegate)
    }

    @MainActor
    func testSelectionUpdateReloadsAndRepairsPreviewIndex() {
        let panel = QuickLookPanelSpy()
        let integration = QuickLookIntegration(panelProvider: { panel })
        integration.handleSpace(for: [
            URL(fileURLWithPath: "/tmp/one.txt"),
            URL(fileURLWithPath: "/tmp/two.txt"),
        ])
        panel.currentPreviewItemIndex = 1

        integration.updateSelection([URL(fileURLWithPath: "/tmp/only.txt")])

        XCTAssertEqual(panel.reloadCount, 2)
        XCTAssertEqual(panel.currentPreviewItemIndex, 0)
    }

    @MainActor
    func testRelinquishDoesNotClearReferencesTakenByAnotherOwner() {
        let panel = QuickLookPanelSpy()
        let integration = QuickLookIntegration(panelProvider: { panel })
        let alternate = QuickLookPanelParticipant()
        integration.handleSpace(for: [URL(fileURLWithPath: "/tmp/item.txt")])
        panel.dataSource = alternate

        integration.relinquishControl()

        XCTAssertTrue(panel.dataSource === alternate)
        XCTAssertNil(panel.delegate)
        XCTAssertEqual(panel.dismissalCount, 0)
    }

    @MainActor
    func testSelectionUpdateDoesNotMutatePanelTakenByAnotherOwner() {
        let panel = QuickLookPanelSpy()
        let integration = QuickLookIntegration(panelProvider: { panel })
        let alternate = QuickLookPanelParticipant()
        integration.handleSpace(for: [URL(fileURLWithPath: "/tmp/old.txt")])
        panel.dataSource = alternate
        panel.delegate = alternate
        panel.currentPreviewItemIndex = 7
        let reloadCount = panel.reloadCount
        let newURL = URL(fileURLWithPath: "/tmp/new.txt")

        integration.updateSelection([newURL])

        XCTAssertEqual(integration.selectedURLs, [newURL])
        XCTAssertEqual(panel.reloadCount, reloadCount)
        XCTAssertEqual(panel.currentPreviewItemIndex, 7)
        XCTAssertTrue(panel.dataSource === alternate)
        XCTAssertTrue(panel.delegate === alternate)
    }

    @MainActor
    func testInvalidatingSelectionDismissesOwnedPanelAndRejectsOldTabItems() {
        let panel = QuickLookPanelSpy()
        let integration = QuickLookIntegration(panelProvider: { panel })
        integration.handleSpace(for: [URL(fileURLWithPath: "/tmp/old-tab.txt")])

        integration.invalidateSelection()

        XCTAssertTrue(integration.selectedURLs.isEmpty)
        XCTAssertEqual(integration.numberOfPreviewItems(in: nil), 0)
        XCTAssertFalse(integration.acceptsPreviewPanelControl(nil))
        XCTAssertEqual(panel.dismissalCount, 1)
        XCTAssertNil(panel.dataSource)
        XCTAssertNil(panel.delegate)
    }

    @MainActor
    func testDetachRestoresResponderChainAndClearsStalePanelReferences() {
        let panel = QuickLookPanelSpy()
        let integration = QuickLookIntegration(panelProvider: { panel })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let previousResponder = window.nextResponder

        integration.install(in: window)
        integration.handleSpace(for: [URL(fileURLWithPath: "/tmp/item.txt")])
        integration.detach()

        XCTAssertTrue(window.nextResponder === previousResponder)
        XCTAssertNil(panel.dataSource)
        XCTAssertNil(panel.delegate)
    }

    @MainActor
    func testWindowCloseNotificationSynchronouslyDetachesResponderAndPanel() {
        let panel = QuickLookPanelSpy()
        let integration = QuickLookIntegration(panelProvider: { panel })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let previousResponder = window.nextResponder
        integration.install(in: window)
        integration.handleSpace(for: [URL(fileURLWithPath: "/tmp/item.txt")])

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        XCTAssertTrue(window.nextResponder === previousResponder)
        XCTAssertEqual(panel.dismissalCount, 1)
        XCTAssertNil(panel.dataSource)
        XCTAssertNil(panel.delegate)
    }
}

@MainActor
private final class QuickLookPanelSpy: QuickLookPanelManaging {
    var identity: ObjectIdentifier { ObjectIdentifier(self) }
    var isVisible = false
    var currentPreviewItemIndex = NSNotFound
    var dataSource: (any QLPreviewPanelDataSource)?
    var delegate: AnyObject?
    private(set) var reloadCount = 0
    private(set) var presentationCount = 0
    private(set) var dismissalCount = 0

    func reloadData() {
        reloadCount += 1
    }

    func present() {
        presentationCount += 1
        isVisible = true
    }

    func dismiss() {
        dismissalCount += 1
        isVisible = false
    }
}

@MainActor
private final class QuickLookPanelParticipant: NSObject,
    @MainActor QLPreviewPanelDataSource,
    @MainActor QLPreviewPanelDelegate
{
    private let item = TestPreviewItem()

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        item
    }
}

private final class TestPreviewItem: NSObject, QLPreviewItem {
    var previewItemURL: URL? { nil }
}
