import Foundation

/// Watches the sessions folder (a file added, replaced or removed) and calls `onChange` on the
/// main actor, debounced, so a burst of hook writes causes one reload. Lives as long as the app.
@MainActor
final class SessionFolderWatcher {
    static let debounce: DispatchTimeInterval = .milliseconds(100)

    private let source: DispatchSourceFileSystemObject
    private let onChange: @MainActor () -> Void
    private var pending: DispatchWorkItem?

    init?(directory: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        self.onChange = onChange
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.schedule() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: item)
    }
}
