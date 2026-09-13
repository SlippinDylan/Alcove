import Foundation
import XCTest
@testable import AlcoveCore

final class SelectionStateTests: XCTestCase {
    func testReplaceSelectionKeepsOnlyCurrentItemsInGridOrder() {
        let ids = (0..<4).map { FileIdentity(url: URL(fileURLWithPath: "/tmp/\($0)")) }
        let missing = FileIdentity(url: URL(fileURLWithPath: "/tmp/missing"))
        var state = SelectionState()

        state.replaceSelection(with: [ids[3], missing, ids[1]], in: ids)

        XCTAssertEqual(state.selectedIDs, [ids[1], ids[3]])
        XCTAssertEqual(state.anchorID, ids[1])
        XCTAssertEqual(state.focusID, ids[3])
    }

    func testReplaceSelectionPreservesPreferredAnchorAndFocusWhenSelected() {
        let ids = (0..<4).map { FileIdentity(url: URL(fileURLWithPath: "/tmp/\($0)")) }
        var state = SelectionState()

        state.replaceSelection(
            with: [ids[0], ids[2], ids[3]],
            in: ids,
            preferredAnchorID: ids[2],
            preferredFocusID: ids[3]
        )

        XCTAssertEqual(state.anchorID, ids[2])
        XCTAssertEqual(state.focusID, ids[3])
    }

    private let ids = ["a", "b", "c", "d"].map {
        FileIdentity(url: URL(fileURLWithPath: "/tmp/selection/\($0)"))
    }

    func testEmptySnapshotCanBeSelectedAndCleared() {
        var state = SelectionState()

        state.selectAll([])
        state.reconcile(with: [])
        state.clear()

        XCTAssertTrue(state.selectedIDs.isEmpty)
        XCTAssertNil(state.anchorID)
        XCTAssertNil(state.focusID)
    }

    func testSelectReplacesSelectionAndEstablishesAnchorAndFocus() {
        var state = SelectionState()
        state.select(ids[0])
        state.select(ids[2])

        XCTAssertEqual(state.selectedIDs, Set([ids[2]]))
        XCTAssertEqual(state.anchorID, ids[2])
        XCTAssertEqual(state.focusID, ids[2])
    }

    func testToggleAddsAndRemovesOnlyTheTarget() {
        var state = SelectionState()
        state.select(ids[0])
        state.toggle(ids[2], in: ids)

        XCTAssertEqual(state.selectedIDs, Set([ids[0], ids[2]]))
        XCTAssertEqual(state.anchorID, ids[2])
        XCTAssertEqual(state.focusID, ids[2])

        state.toggle(ids[2], in: ids)

        XCTAssertEqual(state.selectedIDs, Set([ids[0]]))
        XCTAssertEqual(state.anchorID, ids[0])
        XCTAssertEqual(state.focusID, ids[0])
    }

    func testExtendRangeSelectsForwardInclusiveRange() {
        var state = SelectionState()
        state.select(ids[1])

        state.extendRange(to: ids[3], in: ids)

        XCTAssertEqual(state.selectedIDs, Set([ids[1], ids[2], ids[3]]))
        XCTAssertEqual(state.anchorID, ids[1])
        XCTAssertEqual(state.focusID, ids[3])
    }

    func testExtendRangeSelectsBackwardInclusiveRange() {
        var state = SelectionState()
        state.select(ids[3])

        state.extendRange(to: ids[1], in: ids)

        XCTAssertEqual(state.selectedIDs, Set([ids[1], ids[2], ids[3]]))
        XCTAssertEqual(state.anchorID, ids[3])
        XCTAssertEqual(state.focusID, ids[1])
    }

    func testFocusMoveAndExtensionUseTargetsSuppliedByTheGrid() {
        var state = SelectionState()

        state.moveFocus(to: ids[0])
        state.extendFocus(to: ids[2], in: ids)

        XCTAssertEqual(state.selectedIDs, Set([ids[0], ids[1], ids[2]]))
        XCTAssertEqual(state.anchorID, ids[0])
        XCTAssertEqual(state.focusID, ids[2])
    }

    func testReconcileRemovesStaleIDsAndRepairsAnchorAndFocus() {
        var state = SelectionState()
        state.select(ids[1])
        state.extendRange(to: ids[3], in: ids)

        state.reconcile(with: [ids[0], ids[2]])

        XCTAssertEqual(state.selectedIDs, Set([ids[2]]))
        XCTAssertEqual(state.anchorID, ids[2])
        XCTAssertEqual(state.focusID, ids[2])
    }

    func testReconcileClearsOnlyStaleSelection() {
        var state = SelectionState()
        state.select(ids[1])

        state.reconcile(with: [ids[0]])

        XCTAssertTrue(state.selectedIDs.isEmpty)
        XCTAssertNil(state.anchorID)
        XCTAssertNil(state.focusID)
    }
}
