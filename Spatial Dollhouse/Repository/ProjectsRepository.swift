import Foundation

struct ProjectsRepository {
    private let fileManager: FileManager
    private let documentsURL: URL
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        documentsURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.documentsURL = documentsURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func loadProjects() throws -> [ProjectSummary] {
        guard fileManager.fileExists(atPath: documentsURL.path()) else {
            return []
        }

        let folderURLs = try fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let projects = folderURLs.compactMap { folderURL in
            try? loadProject(at: folderURL)
        }
        return projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func createProject(name: String, imageData: Data, fileExtension: String?) throws -> ProjectSummary {
        let projectID = UUID()
        let folderURL = documentsURL.appendingPathComponent(projectID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let normalizedExtension = normalizedFileExtension(fileExtension)
        let imageFilename = "\(sanitizedFilename(from: name)).\(normalizedExtension)"
        let imageFileURL = folderURL.appendingPathComponent(imageFilename)
        try imageData.write(to: imageFileURL, options: .atomic)

        let metadata = StoredProjectMetadata(
            id: projectID,
            name: name,
            imageFilename: imageFilename,
            modelFilename: nil,
            generationStatus: "idle",
            generationErrorMessage: nil
        )
        try writeMetadata(metadata, in: folderURL)

        return ProjectSummary(
            id: projectID,
            name: name,
            thumbnailData: imageData,
            directoryURL: folderURL,
            imageFileURL: imageFileURL,
            modelFileURL: nil,
            generationState: .idle
        )
    }

    func markGenerationState(
        for projectID: UUID,
        state: ProjectGenerationState
    ) throws -> ProjectSummary {
        let folderURL = documentsURL.appendingPathComponent(projectID.uuidString, isDirectory: true)
        let metadata = try loadMetadata(at: folderURL)
        let updatedMetadata = StoredProjectMetadata(
            id: metadata.id,
            name: metadata.name,
            imageFilename: metadata.imageFilename,
            modelFilename: metadata.modelFilename,
            generationStatus: state.statusValue,
            generationErrorMessage: generationErrorMessage(for: state)
        )
        try writeMetadata(updatedMetadata, in: folderURL)
        guard let project = try loadPersistedProject(at: folderURL, metadata: updatedMetadata) else {
            throw ProjectsRepositoryError.projectAssetsMissing
        }
        return project
    }

    func saveGeneratedModel(
        for projectID: UUID,
        named filename: String,
        modelDataProvider: (URL) async throws -> Void
    ) async throws -> ProjectSummary {
        let folderURL = documentsURL.appendingPathComponent(projectID.uuidString, isDirectory: true)
        let metadata = try loadMetadata(at: folderURL)
        let normalizedFilename = normalizedModelFilename(filename)
        let modelFileURL = folderURL.appendingPathComponent(normalizedFilename)
        try await modelDataProvider(modelFileURL)

        let updatedMetadata = StoredProjectMetadata(
            id: metadata.id,
            name: metadata.name,
            imageFilename: metadata.imageFilename,
            modelFilename: normalizedFilename,
            generationStatus: ProjectGenerationState.ready.statusValue,
            generationErrorMessage: nil
        )
        try writeMetadata(updatedMetadata, in: folderURL)
        guard let project = try loadPersistedProject(at: folderURL, metadata: updatedMetadata) else {
            throw ProjectsRepositoryError.projectAssetsMissing
        }
        return project
    }

    private func loadProject(at folderURL: URL) throws -> ProjectSummary? {
        let values = try folderURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            return nil
        }

        let metadataURL = folderURL.appendingPathComponent("project.json")
        guard fileManager.fileExists(atPath: metadataURL.path()) else {
            return nil
        }

        var metadata = try loadMetadata(at: folderURL)
        if metadata.generationStatus == ProjectGenerationState.generating.statusValue {
            metadata = StoredProjectMetadata(
                id: metadata.id,
                name: metadata.name,
                imageFilename: metadata.imageFilename,
                modelFilename: metadata.modelFilename,
                generationStatus: "failed",
                generationErrorMessage: "3D generation was interrupted before completion."
            )
            try writeMetadata(metadata, in: folderURL)
        }

        return try loadPersistedProject(at: folderURL, metadata: metadata)
    }

    private func sanitizedFilename(from name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let pieces = name.components(separatedBy: invalidCharacters)
        let collapsed = pieces.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = collapsed.replacingOccurrences(of: " ", with: "-")
        return compact.isEmpty ? "Project" : compact
    }

    private func normalizedFileExtension(_ fileExtension: String?) -> String {
        let candidate = (fileExtension ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")

        return candidate.isEmpty ? "jpg" : candidate
    }

    private func normalizedModelFilename(_ filename: String) -> String {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileURL = URL(fileURLWithPath: trimmedFilename)
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension.isEmpty ? "obj" : fileURL.pathExtension.lowercased()
        let normalizedStem = sanitizedFilename(from: stem)
        return "\(normalizedStem).\(ext)"
    }

    private func loadPersistedProject(at folderURL: URL, metadata: StoredProjectMetadata) throws -> ProjectSummary? {
        let imageFileURL = folderURL.appendingPathComponent(metadata.imageFilename)
        guard fileManager.fileExists(atPath: imageFileURL.path()) else {
            return nil
        }

        let imageData = try Data(contentsOf: imageFileURL)
        let modelFileURL = metadata.modelFilename.map { folderURL.appendingPathComponent($0) }
        let resolvedModelFileURL: URL?
        if let modelFileURL, fileManager.fileExists(atPath: modelFileURL.path()) {
            resolvedModelFileURL = modelFileURL
        } else {
            resolvedModelFileURL = nil
        }

        let generationState = projectGenerationState(
            from: metadata,
            modelFileURL: resolvedModelFileURL
        )

        return ProjectSummary(
            id: metadata.id,
            name: metadata.name,
            thumbnailData: imageData,
            directoryURL: folderURL,
            imageFileURL: imageFileURL,
            modelFileURL: resolvedModelFileURL,
            generationState: generationState
        )
    }

    private func loadMetadata(at folderURL: URL) throws -> StoredProjectMetadata {
        let metadataURL = folderURL.appendingPathComponent("project.json")
        let metadataData = try Data(contentsOf: metadataURL)
        return try jsonDecoder.decode(StoredProjectMetadata.self, from: metadataData)
    }

    private func writeMetadata(_ metadata: StoredProjectMetadata, in folderURL: URL) throws {
        let metadataURL = folderURL.appendingPathComponent("project.json")
        let metadataData = try jsonEncoder.encode(metadata)
        try metadataData.write(to: metadataURL, options: .atomic)
    }

    private func projectGenerationState(
        from metadata: StoredProjectMetadata,
        modelFileURL: URL?
    ) -> ProjectGenerationState {
        switch metadata.generationStatus {
        case ProjectGenerationState.idle.statusValue:
            return .idle
        case ProjectGenerationState.generating.statusValue:
            return .generating
        case ProjectGenerationState.ready.statusValue:
            if modelFileURL == nil {
                return .failed("The saved 3D model could not be found in the project folder.")
            }
            return .ready
        case "failed":
            return .failed(metadata.generationErrorMessage ?? "")
        default:
            return .failed(metadata.generationErrorMessage ?? "3D model generation failed.")
        }
    }

    private func generationErrorMessage(for state: ProjectGenerationState) -> String? {
        switch state {
        case .failed(let message):
            return message.isEmpty ? nil : message
        case .idle, .generating, .ready:
            return nil
        }
    }
}

private enum ProjectsRepositoryError: LocalizedError {
    case projectAssetsMissing

    var errorDescription: String? {
        switch self {
        case .projectAssetsMissing:
            return "The project files could not be reloaded from disk."
        }
    }
}
