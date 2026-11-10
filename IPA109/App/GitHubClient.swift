import Foundation

struct GitHubClient {
    let config: UserConfig

    private var owner: String { config.githubOwner.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var repo: String { config.githubRepo.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var base: String { "https://api.github.com/repos/\(owner)/\(repo)" }

    private func validate() throws {
        guard !config.githubToken.isEmpty, !owner.isEmpty, !repo.isEmpty else {
            throw IPAError.missingSettings("أضف GitHub Token واسم الحساب والمستودع من الإعدادات.")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard owner.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              repo.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw IPAError.missingSettings("اسم GitHub أو المستودع يحتوي على رموز غير مدعومة.")
        }
    }

    private func call(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                      query: [URLQueryItem] = []) async throws -> (Int, Data) {
        try validate()
        guard var components = URLComponents(string: base + path) else { throw IPAError.invalidResponse("عنوان GitHub غير صالح.") }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw IPAError.invalidResponse("عنوان الطلب غير صالح.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("Bearer \(config.githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw IPAError.invalidResponse("لم يصل رد من GitHub.") }
        return (response.statusCode, data)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IPAError.invalidResponse("رد GitHub غير صالح.")
        }
        return value
    }

    private func expectSuccess(_ status: Int, _ data: Data) throws {
        guard (200...299).contains(status) else {
            let explanation = (try? object(data)["message"] as? String) ?? "خطأ غير معروف"
            throw IPAError.serverMessage("GitHub (\(status)): \(explanation)")
        }
    }

    func startBuild(project: AppProject) async throws -> BuildResult {
        guard !project.html.isEmpty else { throw IPAError.missingSettings("أنشئ التطبيق أولاً قبل التصدير.") }
        let branch = "ipa109-build-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12)
        let shortID = project.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12)
        let tag = "ipa109-app-\(shortID)-\(UUID().uuidString.prefix(8).lowercased())"
        let sourceBranch = config.githubBranch.isEmpty ? "main" : config.githubBranch

        let (refStatus, refData) = try await call("/git/ref/heads/\(sourceBranch)")
        try expectSuccess(refStatus, refData)
        guard let refObject = try object(refData)["object"] as? [String: Any],
              let commitSHA = refObject["sha"] as? String else {
            throw IPAError.invalidResponse("تعذر قراءة فرع GitHub الأساسي.")
        }

        let (createStatus, createData) = try await call("/git/refs", method: "POST", body: [
            "ref": "refs/heads/\(branch)", "sha": commitSHA
        ])
        try expectSuccess(createStatus, createData)

        let contentPath = "/contents/GeneratedApp/Resources/webapp.html"
        let (fileStatus, fileData) = try await call(contentPath, query: [URLQueryItem(name: "ref", value: branch)])
        try expectSuccess(fileStatus, fileData)
        guard let oldSHA = try object(fileData)["sha"] as? String else {
            throw IPAError.invalidResponse("لم أجد القالب الأساسي للتطبيق داخل مستودع GitHub.")
        }
        let (putStatus, putData) = try await call(contentPath, method: "PUT", body: [
            "message": "IPA109: build generated project \(shortID)",
            "content": Data(project.html.utf8).base64EncodedString(),
            "sha": oldSHA,
            "branch": branch
        ])
        try expectSuccess(putStatus, putData)

        let (dispatchStatus, dispatchData) = try await call("/actions/workflows/build-generated.yml/dispatches", method: "POST", body: [
            "ref": branch,
            "inputs": ["tag": tag, "project_id": String(shortID), "title": String(project.title.prefix(50))]
        ])
        try expectSuccess(dispatchStatus, dispatchData)
        return BuildResult(tag: tag, releaseURL: "https://github.com/\(owner)/\(repo)/releases/tag/\(tag)")
    }

    func releaseIPA(tag: String) async throws -> String? {
        let (status, data) = try await call("/releases/tags/\(tag)")
        if status == 404 { return nil }
        try expectSuccess(status, data)
        guard let assets = try object(data)["assets"] as? [[String: Any]],
              let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".ipa") == true }),
              let url = asset["browser_download_url"] as? String else { return nil }
        return url
    }
}
