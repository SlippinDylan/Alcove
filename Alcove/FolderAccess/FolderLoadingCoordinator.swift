import Foundation

struct FolderLoadRequest: Equatable, Sendable {
    let generation: UInt64
}

enum FolderLoadOutcome: Equatable, Sendable {
    case contents(FolderEnumerationResult)
    case failure(FolderAccessError)
}

enum FolderLoadCompletion: Equatable, Sendable {
    case accepted(request: FolderLoadRequest, outcome: FolderLoadOutcome)
    case discarded(request: FolderLoadRequest)
}

actor FolderLoadingCoordinator {
    private let enumerator: any FolderEnumerating
    private var currentGeneration: UInt64 = 0

    init(enumerator: any FolderEnumerating = FolderEnumerator()) {
        self.enumerator = enumerator
    }

    func load(root: URL, showHidden: Bool = false) async throws -> FolderLoadCompletion {
        guard currentGeneration < UInt64.max else {
            throw FolderLoadingError.generationExhausted
        }
        currentGeneration += 1
        let request = FolderLoadRequest(generation: currentGeneration)

        let outcome: FolderLoadOutcome
        do {
            outcome = .contents(
                try await enumerator.enumerate(
                    root: root,
                    showHidden: showHidden,
                    generation: request.generation
                )
            )
        } catch is CancellationError {
            return .discarded(request: request)
        } catch let error as FolderAccessError {
            outcome = .failure(error)
        } catch let error as NSError {
            outcome = .failure(FolderAccessError.classifyRootError(url: root, error: error))
        }

        guard !Task.isCancelled, request.generation == currentGeneration else {
            return .discarded(request: request)
        }
        return .accepted(request: request, outcome: outcome)
    }

    func cancelCurrentLoad() {
        if currentGeneration < UInt64.max {
            currentGeneration += 1
        }
    }
}

enum FolderLoadingError: Error, Equatable, Sendable {
    case generationExhausted
}
