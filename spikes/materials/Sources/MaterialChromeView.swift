// MaterialChromeView.swift
// Alcove Spike 0.4A — Material Compatibility Boundary Bootstrap

import AppKit

@MainActor
final class MaterialChromeView: NSView {
    typealias GroupWrapper = @MainActor (NSView) -> NSView

    let segmentedControl = NSSegmentedControl()
    let addButton = NSButton()
    let closeButton = NSButton()
    private(set) var groupContainers: [NSView] = []

    var onAddRequested: (() -> Void)?
    var onCloseRequested: (() -> Void)?

    var tabCount: Int { segmentedControl.segmentCount }

    init(groupWrapper: GroupWrapper = { $0 }) {
        super.init(frame: .zero)
        buildControls(groupWrapper: groupWrapper)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func buildControls(groupWrapper: GroupWrapper) {
        let tabContent = NSView()
        tabContent.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.segmentCount = 3
        for (index, title) in ["Documents", "Images", "Projects"].enumerated() {
            segmentedControl.setLabel(title, forSegment: index)
            segmentedControl.setWidth(0, forSegment: index)
        }
        segmentedControl.selectedSegment = 0
        segmentedControl.segmentStyle = .rounded
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        tabContent.addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: tabContent.topAnchor, constant: 6),
            segmentedControl.leadingAnchor.constraint(equalTo: tabContent.leadingAnchor, constant: 8),
            segmentedControl.trailingAnchor.constraint(equalTo: tabContent.trailingAnchor, constant: -8),
            segmentedControl.bottomAnchor.constraint(equalTo: tabContent.bottomAnchor, constant: -6),
        ])

        let buttonContent = NSView()
        buttonContent.translatesAutoresizingMaskIntoConstraints = false
        configureButton(addButton, title: "+", action: #selector(addTabPressed))
        configureButton(closeButton, title: "–", action: #selector(closeTabPressed))
        buttonContent.addSubview(addButton)
        buttonContent.addSubview(closeButton)
        NSLayoutConstraint.activate([
            addButton.topAnchor.constraint(equalTo: buttonContent.topAnchor, constant: 6),
            addButton.leadingAnchor.constraint(equalTo: buttonContent.leadingAnchor, constant: 8),
            addButton.bottomAnchor.constraint(equalTo: buttonContent.bottomAnchor, constant: -6),
            closeButton.topAnchor.constraint(equalTo: buttonContent.topAnchor, constant: 6),
            closeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: buttonContent.trailingAnchor, constant: -8),
            closeButton.bottomAnchor.constraint(equalTo: buttonContent.bottomAnchor, constant: -6),
        ])

        let tabContainer = groupWrapper(tabContent)
        let buttonContainer = groupWrapper(buttonContent)
        groupContainers = [tabContainer, buttonContainer]
        groupContainers.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            tabContainer.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            tabContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            tabContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            buttonContainer.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            buttonContainer.leadingAnchor.constraint(equalTo: tabContainer.trailingAnchor, constant: 8),
            buttonContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            buttonContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])

        segmentedControl.setAccessibilityLabel("Portal tabs")
        addButton.setAccessibilityLabel("Add tab")
        closeButton.setAccessibilityLabel("Close tab")
    }

    private func configureButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .inline
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = action
    }

    @objc private func addTabPressed() {
        onAddRequested?()
    }

    @objc private func closeTabPressed() {
        onCloseRequested?()
    }
}

@MainActor
final class OpaqueChromeBackgroundView: NSView {
    override var isOpaque: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}
