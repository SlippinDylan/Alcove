import AlcoveCore
import AppKit

@MainActor
final class ApplicationSettingsCardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    init(rows: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        var arrangedViews: [NSView] = []
        for (index, row) in rows.enumerated() {
            arrangedViews.append(row)
            if index < rows.count - 1 {
                let separator = NSBox()
                separator.boxType = .separator
                separator.identifier = NSUserInterfaceItemIdentifier(
                    "application-settings.row-separator"
                )
                arrangedViews.append(separator)
            }
        }
        let stack = NSStackView(views: arrangedViews)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        }
    }
}

@MainActor
final class VersionBadgeView: NSView {
    override var wantsUpdateLayer: Bool { true }

    private let label: NSTextField

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        identifier = NSUserInterfaceItemIdentifier("application-settings.version-badge")
        setAccessibilityLabel(text)

        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: label.intrinsicContentSize.width + 18, height: 22)
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        }
    }
}
