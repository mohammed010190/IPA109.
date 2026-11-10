import Foundation
import Combine

struct ChatEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var isUser: Bool
}

struct AppProject: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var html: String = ""
    var messages: [ChatEntry] = []
    var createdAt: Date = Date()
    var buildTag: String? = nil
    var ipaURL: String? = nil
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [AppProject] = []
    private let storageKey = "ipa109-projects-v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AppProject].self, from: data) {
            projects = decoded
        }
    }

    @discardableResult
    func create() -> UUID {
        let new = AppProject(title: "تطبيق جديد")
        projects.insert(new, at: 0)
        save()
        return new.id
    }

    func mutate(_ id: UUID, action: (inout AppProject) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        action(&projects[index])
        save()
    }

    func delete(at offsets: IndexSet) {
        projects.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

struct AIResult: Decodable {
    let title: String
    let html: String
    let message: String
}

struct BuildResult {
    let tag: String
    let releaseURL: String
}

enum IPAError: LocalizedError {
    case missingSettings(String)
    case invalidResponse(String)
    case serverMessage(String)
    var errorDescription: String? {
        switch self {
        case .missingSettings(let message), .invalidResponse(let message), .serverMessage(let message): return message
        }
    }
}
