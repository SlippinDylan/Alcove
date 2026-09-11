# Slice 1 — App Shell and Menu Bar

## Goal

Create the first production Alcove Xcode project as a macOS 15 AppKit LSUIElement
application with a menu-bar status item, disabled New Portal command, Quit
command, and host unit tests. Formal signing is out of scope.

## Boundaries

- Use Swift 6 complete strict concurrency and warnings as errors.
- Build a universal arm64 + x86_64 application.
- Do not add Portal, persistence, folder access, or speculative packages.
- Do not claim manual menu-bar/Dock/quit behavior without visual execution.

## Verification

- Xcode project and shared scheme discovery.
- Host unit tests for app lifecycle and status-menu structure/ownership.
- Unsigned universal Release build and Info.plist inspection.
