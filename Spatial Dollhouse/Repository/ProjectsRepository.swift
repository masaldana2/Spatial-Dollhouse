import Foundation
import SwiftData

@MainActor
struct ProjectsRepository {
    private let fileManager: FileManager
    private let documentsURL: URL
    private let appDataStore: AppDataStore

    init(
        appDataStore: AppDataStore,
        fileManager: FileManager = .default,
        documentsURL: URL? = nil
    ) {
        self.appDataStore = appDataStore
        self.fileManager = fileManager
        self.documentsURL = documentsURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func loadProjects() throws -> [ProjectSummary] {
        try fetchProjects().compactMap { record in
            try? loadProject(from: record)
        }
    }

    func createProject(name: String, imageData: Data, fileExtension: String?) throws -> ProjectSummary {
        let projectID = UUID()
        let directoryName = projectID.uuidString
        let folderURL = projectFolderURL(directoryName: directoryName)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let normalizedExtension = normalizedFileExtension(fileExtension)
        let imageFilename = "\(sanitizedFilename(from: name)).\(normalizedExtension)"
        let imageFileURL = folderURL.appendingPathComponent(imageFilename)
        try imageData.write(to: imageFileURL, options: .atomic)

        let timestamp = Date()
        let record = ProjectRecord(
            id: projectID,
            name: name,
            directoryName: directoryName,
            imageFilename: imageFilename,
            modelFilename: nil,
            generationStatus: ProjectGenerationState.idle.statusValue,
            generationErrorMessage: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        appDataStore.modelContainer.mainContext.insert(record)
        try appDataStore.modelContainer.mainContext.save()

        guard let project = try loadPersistedProject(from: record) else {
            throw ProjectsRepositoryError.projectAssetsMissing
        }

        return project
    }

    func markGenerationState(
        for projectID: UUID,
        state: ProjectGenerationState
    ) throws -> ProjectSummary {
        let updatedRecord = try updateProject(id: projectID) { record in
            record.generationStatus = state.statusValue
            record.generationErrorMessage = generationErrorMessage(for: state)
        }
        guard let project = try loadPersistedProject(from: updatedRecord) else {
            throw ProjectsRepositoryError.projectAssetsMissing
        }
        return project
    }

    func saveGeneratedModel(
        for projectID: UUID,
        named filename: String,
        modelDataProvider: (URL) async throws -> Void
    ) async throws -> ProjectSummary {
        let record = try fetchProject(id: projectID)
        let folderURL = projectFolderURL(directoryName: record.directoryName)
        let normalizedFilename = normalizedModelFilename(filename)
        let modelFileURL = folderURL.appendingPathComponent(normalizedFilename)
        try await modelDataProvider(modelFileURL)

        let updatedRecord = try updateProject(id: projectID) { project in
            project.modelFilename = normalizedFilename
            project.generationStatus = ProjectGenerationState.ready.statusValue
            project.generationErrorMessage = nil
        }
        guard let project = try loadPersistedProject(from: updatedRecord) else {
            throw ProjectsRepositoryError.projectAssetsMissing
        }
        return project
    }

    private func loadProject(from record: ProjectRecord) throws -> ProjectSummary? {
        if record.generationStatus == ProjectGenerationState.generating.statusValue {
            let interruptedRecord = try updateProject(id: record.id) { project in
                project.generationStatus = ProjectGenerationState.failed("").statusValue
                project.generationErrorMessage = "3D generation was interrupted before completion."
            }
            return try loadPersistedProject(from: interruptedRecord)
        }

        return try loadPersistedProject(from: record)
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

    private func loadPersistedProject(from record: ProjectRecord) throws -> ProjectSummary? {
        let folderURL = projectFolderURL(directoryName: record.directoryName)
        let imageFileURL = folderURL.appendingPathComponent(record.imageFilename)
        guard fileManager.fileExists(atPath: imageFileURL.path()) else {
            return nil
        }

        let imageData = try Data(contentsOf: imageFileURL)
        let modelFileURL = record.modelFilename.map { folderURL.appendingPathComponent($0) }
        let resolvedModelFileURL: URL?
        if let modelFileURL, fileManager.fileExists(atPath: modelFileURL.path()) {
            resolvedModelFileURL = modelFileURL
        } else {
            resolvedModelFileURL = nil
        }

        let generationState = projectGenerationState(
            from: record,
            modelFileURL: resolvedModelFileURL
        )

        return ProjectSummary(
            id: record.id,
            name: record.name,
            thumbnailData: imageData,
            directoryURL: folderURL,
            imageFileURL: imageFileURL,
            modelFileURL: resolvedModelFileURL,
            generationState: generationState
        )
    }

    private func projectFolderURL(directoryName: String) -> URL {
        documentsURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    private func fetchProjects() throws -> [ProjectRecord] {
        let descriptor = FetchDescriptor<ProjectRecord>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try appDataStore.modelContainer.mainContext.fetch(descriptor)
    }

    private func fetchProject(id: UUID) throws -> ProjectRecord {
        var descriptor = FetchDescriptor<ProjectRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        guard let record = try appDataStore.modelContainer.mainContext.fetch(descriptor).first else {
            throw ProjectsRepositoryError.projectNotFound(id)
        }

        return record
    }

    private func updateProject(
        id: UUID,
        mutate: (ProjectRecord) -> Void
    ) throws -> ProjectRecord {
        let record = try fetchProject(id: id)
        mutate(record)
        record.updatedAt = Date()
        try appDataStore.modelContainer.mainContext.save()
        return record
    }

    private func projectGenerationState(
        from record: ProjectRecord,
        modelFileURL: URL?
    ) -> ProjectGenerationState {
        switch record.generationStatus {
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
            return .failed(record.generationErrorMessage ?? "")
        default:
            return .failed(record.generationErrorMessage ?? "3D model generation failed.")
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
    case projectNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .projectAssetsMissing:
            return "The project files could not be reloaded from disk."
        case .projectNotFound(let id):
            return "Project \(id.uuidString) could not be found in the repository."
        }
    }
}
