import AlcoveCore
import AppKit

@MainActor
enum PortalLayoutPlanner {
    struct SpacingEntry {
        let id: PortalID
        let frame: NSRect
    }

    struct IconSizeEntry {
        let id: PortalID
        let gridCapacity: GridCapacity
        let referenceFrame: NSRect
    }

    static func spacingPlan(
        snapshot: DisplaySnapshot,
        spacing: CGFloat,
        entries: [SpacingEntry]
    ) -> [PortalID: NSRect]? {
        var entriesByDisplay: [DisplayIdentity: [SpacingEntry]] = [:]
        for entry in entries {
            guard let display = try? LegacyFrameDisplayResolver.resolve(
                frame: entry.frame,
                in: snapshot
            ) else {
                return nil
            }
            entriesByDisplay[display.identity, default: []].append(entry)
        }

        var plan: [PortalID: NSRect] = [:]
        for display in snapshot.displays {
            guard let displayEntries = entriesByDisplay[display.identity] else { continue }
            let result: [NSRect]?
            do {
                result = try PortalFrameReflow.reflowedFrames(
                    displayEntries.map(\.frame),
                    visibleFrame: display.visibleFrame,
                    minimumGap: spacing
                )
            } catch {
                return nil
            }
            guard let reflowedFrames = result else { return nil }
            for (entry, frame) in zip(displayEntries, reflowedFrames) {
                plan[entry.id] = frame
            }
        }
        return plan
    }

    static func iconSizePlan(
        snapshot: DisplaySnapshot,
        iconSize: IconSize,
        spacing: CGFloat,
        entries: [IconSizeEntry]
    ) -> [PortalID: NSRect]? {
        let iconLayout = PortalIconLayout.fixed(iconSize)
        var entriesByDisplay: [DisplayIdentity: [(
            entry: IconSizeEntry,
            targetFrame: NSRect
        )]] = [:]

        for entry in entries {
            guard let display = try? LegacyFrameDisplayResolver.resolve(
                frame: entry.referenceFrame,
                in: snapshot
            ) else {
                return nil
            }
            let contentSize = PortalViewController.contentSize(
                for: entry.gridCapacity,
                iconLayout: iconLayout
            )
            let frameSize = NSWindow.frameRect(
                forContentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.resizable]
            ).size
            let targetFrame = NSRect(
                x: entry.referenceFrame.minX,
                y: entry.referenceFrame.maxY - frameSize.height,
                width: frameSize.width,
                height: frameSize.height
            )
            entriesByDisplay[display.identity, default: []].append((entry, targetFrame))
        }

        var plan: [PortalID: NSRect] = [:]
        for display in snapshot.displays {
            guard let displayEntries = entriesByDisplay[display.identity] else { continue }
            let result: [NSRect]?
            do {
                result = try PortalFrameReflow.reflowedFrames(
                    displayEntries.map(\.targetFrame),
                    attachmentReferenceFrames: displayEntries.map(\.entry.referenceFrame),
                    visibleFrame: display.visibleFrame,
                    minimumGap: spacing
                )
            } catch {
                return nil
            }
            guard let reflowedFrames = result else { return nil }
            for (entry, frame) in zip(displayEntries, reflowedFrames) {
                plan[entry.entry.id] = frame
            }
        }
        return plan
    }
}
