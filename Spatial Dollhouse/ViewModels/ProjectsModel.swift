import Foundation
import ImageIO
import Observation

@MainActor
@Observable
final class ProjectsModel {
    var projects: [ProjectSummary]
    var isImportOptionsPresented = false
    var isFileImporterPresented = false
    var isNamingSheetPresented = false
    var draftImageData: Data?
    var draftImageFileExtension: String?
    var draftProjectName = ""
    var importMessage: String?

    private let repository: ProjectsRepository
    private let generationPipeline: ProjectModelGenerationPipeline
    private var generationTasks: [UUID: Task<Void, Never>] = [:]

    init(
        repository: ProjectsRepository,
        generationPipeline: ProjectModelGenerationPipeline? = nil
    ) {
        self.repository = repository
        self.generationPipeline = generationPipeline ?? ProjectModelGenerationPipeline()
        do {
            self.projects = try repository.loadProjects()
        } catch {
            self.projects = []
            self.importMessage = error.localizedDescription
        }
    }

    func startFileImport() {
        isImportOptionsPresented = false
        isFileImporterPresented = true
        importMessage = nil
    }

    func handleFileImportResult(_ result: Result<URL, any Error>) {
        Task {
            do {
                let url = try result.get()
                let imageData = try await loadImageData(from: url)
                presentDraft(for: imageData, fileExtension: url.pathExtension)
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }

    func handlePhotoSelection(data: Data?, fileExtension: String? = nil) {
        guard let data else { return }
        isImportOptionsPresented = false
        importMessage = nil
        do {
            try validateImageData(data)
            presentDraft(for: data, fileExtension: fileExtension)
        } catch {
            importMessage = error.localizedDescription
        }
    }

    func completeDraftNaming() {
        let trimmedName = draftProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            importMessage = "Enter a project name to continue."
            return
        }
        guard let draftImageData else {
            importMessage = "Select an image before saving the project."
            return
        }

        do {
            let createdProject = try repository.createProject(
                name: trimmedName,
                imageData: draftImageData,
                fileExtension: draftImageFileExtension
            )
            var generatingProject = createdProject
            generatingProject.generationState = .generating
            upsertProject(generatingProject)
            importMessage = "Saved project \"\(trimmedName)\". Generating 3D model..."
            resetDraft()
            enqueueGeneration(for: generatingProject)
        } catch {
            importMessage = error.localizedDescription
        }
    }

    func cancelDraftNaming() {
        resetDraft()
    }

    private func presentDraft(for imageData: Data, fileExtension: String?) {
        draftImageData = imageData
        draftImageFileExtension = fileExtension
        draftProjectName = "Project \(projects.count + 1)"
        isNamingSheetPresented = true
    }

    private func resetDraft() {
        draftImageData = nil
        draftImageFileExtension = nil
        draftProjectName = ""
        isNamingSheetPresented = false
    }

    private func enqueueGeneration(for project: ProjectSummary) {
        guard generationTasks[project.id] == nil else { return }
        guard project.generationState != .ready else { return }

        generationTasks[project.id] = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runGeneration(for: project.id)
        }
    }

    private func runGeneration(for projectID: UUID) async {
        defer { generationTasks[projectID] = nil }

        guard let project = projects.first(where: { $0.id == projectID }) else { return }

        do {
            let generatingProject = try repository.markGenerationState(
                for: project.id,
                state: .generating
            )
            upsertProject(generatingProject)

            let generatedAsset = try await generationPipeline.generateModelAsset(for: generatingProject)
            let readyProject = try await repository.saveGeneratedModel(
                for: generatingProject.id,
                named: generatedAsset.filename
            ) { outputURL in
                try await generatedAsset.write(to: outputURL)
            }
            upsertProject(readyProject)
        } catch {
            let failedProject = try? repository.markGenerationState(
                for: project.id,
                state: .failed(error.localizedDescription)
            )
            if let failedProject {
                upsertProject(failedProject)
            }
            importMessage = error.localizedDescription
        }
    }

    private func upsertProject(_ project: ProjectSummary) {
        if let existingIndex = projects.firstIndex(where: { $0.id == project.id }) {
            projects[existingIndex] = project
        } else {
            projects.append(project)
        }
        projects.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadImageData(from url: URL) async throws -> Data {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value

        try validateImageData(data)
        return data
    }

    private func validateImageData(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw ProjectsImportError.invalidImage
        }
    }
}

private enum ProjectsImportError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected file could not be loaded as an image."
        }
    }
}
