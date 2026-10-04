import Foundation

/// A show plus where (if anywhere) its audio was found on disk.
public struct ShowEntry: Sendable, Hashable, Identifiable {
    public var definition: ShowDefinition
    /// `nil` when the audio file is missing, e.g. a user-supplied track that has not been added yet.
    public var audioURL: URL?

    public var id: String { definition.id }
    public var isPlayable: Bool { audioURL != nil }

    public init(definition: ShowDefinition, audioURL: URL?) {
        self.definition = definition
        self.audioURL = audioURL
    }
}

/// Discovers `*.show.json` files and resolves their audio by file name.
///
/// Everything is found by searching a resource root recursively, so it works whether the
/// build copies resources flat into the bundle or preserves their folders.
public struct ShowCatalog: Sendable {
    public static let showFileSuffix = ".show.json"

    /// A show file that could not be loaded; surfaced so authors can fix it.
    public struct LoadIssue: Sendable, Hashable {
        public var fileName: String
        public var reason: String
    }

    /// Shows in file-name order (prefix files with numbers to control ordering).
    public private(set) var entries: [ShowEntry] = []
    public private(set) var issues: [LoadIssue] = []

    public init(resourceRoot: URL, fileManager: FileManager = .default) {
        var showFiles: [URL] = []
        var filesByName: [String: URL] = [:]
        let enumerator = fileManager.enumerator(at: resourceRoot, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let name = url.lastPathComponent
            if name.hasSuffix(Self.showFileSuffix) {
                showFiles.append(url)
            } else if filesByName[name] == nil {
                filesByName[name] = url
            }
        }
        showFiles.sort { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        for file in showFiles {
            do {
                let definition = try decoder.decode(ShowDefinition.self, from: Data(contentsOf: file))
                try definition.validate()
                entries.append(ShowEntry(definition: definition, audioURL: filesByName[definition.audio.fileName]))
            } catch {
                issues.append(LoadIssue(fileName: file.lastPathComponent, reason: String(describing: error)))
            }
        }
    }
}
