// QuickLookController.swift
// Alcove Spike 0.3A — Quick Look Responder Bootstrap
// Disposable harness; not production architecture.

import AppKit
import Quartz

@MainActor
final class QuickLookResponder: NSResponder,
    @MainActor QLPreviewPanelDataSource,
    @MainActor QLPreviewPanelDelegate
{
    enum SpaceAction: Equatable, Sendable {
        case noOp
        case present
        case dismiss
    }

    private(set) var fixtures: [PreviewFixture] = []
    private(set) var selectedIndices: [Int] = []
    private(set) var selectedPreviewItems: [FixturePreviewItem] = []
    private(set) weak var controlledPanel: QLPreviewPanel?
    private(set) weak var presentationPanel: QLPreviewPanel?
    private let unavailablePreviewItem = UnavailablePreviewItem()

    var onPresentationRequested: (() -> Void)?
    var onDismissalRequested: (() -> Void)?

    func setFixtures(_ newFixtures: [PreviewFixture]) {
        fixtures = newFixtures
        setSelectedIndices([])
    }

    func setSelectedIndices(_ indices: [Int]) {
        selectedIndices = Array(Set(indices.filter(fixtures.indices.contains))).sorted()
        selectedPreviewItems = selectedIndices.map { FixturePreviewItem(fixture: fixtures[$0]) }

        guard let panel = controlledPanel else { return }
        panel.reloadData()
        if selectedPreviewItems.isEmpty {
            panel.currentPreviewItemIndex = NSNotFound
        } else if !selectedPreviewItems.indices.contains(panel.currentPreviewItemIndex) {
            panel.currentPreviewItemIndex = 0
        }
    }

    func spaceAction(panelIsVisible: Bool) -> SpaceAction {
        guard !selectedPreviewItems.isEmpty else { return .noOp }
        return panelIsVisible ? .dismiss : .present
    }

    func togglePanel() {
        let panelIsVisible = presentationPanel?.isVisible ?? false
        switch spaceAction(panelIsVisible: panelIsVisible) {
        case .noOp:
            return
        case .present:
            requestPresentation()
        case .dismiss:
            requestDismissal()
        }
    }

    func requestPresentation() {
        guard !selectedPreviewItems.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        presentationPanel = panel
        panel.makeKeyAndOrderFront(nil)
        onPresentationRequested?()
    }

    func requestDismissal() {
        guard let panel = presentationPanel, panel.isVisible else { return }
        panel.orderOut(nil)
        onDismissalRequested?()
    }

    /// Removes only references still assigned to this responder.
    /// This is required because QuickLookUI imports these Objective-C `assign` properties
    /// without automatic zeroing.
    func teardownPanelState() {
        if let panel = presentationPanel, panel.isVisible {
            panel.orderOut(nil)
        }
        if let panel = controlledPanel {
            releasePanelReferencesIfOwned(panel)
        }
        controlledPanel = nil
        presentationPanel = nil
        fixtures = []
        selectedIndices = []
        selectedPreviewItems = []
    }

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated {
            !selectedPreviewItems.isEmpty
        }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            guard let panel else { return }
            controlledPanel = panel
            presentationPanel = panel
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            guard let panel else { return }
            releasePanelReferencesIfOwned(panel)
            if controlledPanel === panel {
                controlledPanel = nil
            }
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        selectedPreviewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        guard selectedPreviewItems.indices.contains(index) else {
            return unavailablePreviewItem
        }
        return selectedPreviewItems[index]
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        false
    }

    func releasePanelReferencesIfOwned(_ panel: QLPreviewPanel) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if panel.delegate === self {
            panel.delegate = nil
        }
    }
}
