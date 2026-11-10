import Foundation

struct GitHubClient {
    let config: UserConfig

    private var owner: String { config.githubOwner.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var repo: String { config.githubRepo.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var base: String { "https://api.github.com/repos/\(owner)/\(repo)" }

    private func validate() throws {
        guard !config.githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !owner.isEmpty, !repo.isEmpty else {
            throw IPAError.missingSettings("أدخل اسم حساب GitHub واسم المستودع والرمز السري، ثم اضغط حفظ الإعدادات.")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard owner.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              repo.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw IPAError.missingSettings("اسم حساب GitHub أو المستودع يحتوي على رموز غير مدعومة.")
        }
    }

    private func call(_ path: String,
                      method: String = "GET",
                      body: [String: Any]? = nil,
                      query: [URLQueryItem] = []) async throws -> (Int, Data) {
        try validate()
        guard var components = URLComponents(string: base + path) else {
            throw IPAError.invalidResponse("عنوان GitHub غير صالح.")
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw IPAError.invalidResponse("تعذر إنشاء عنوان طلب GitHub.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("Bearer \(config.githubToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IPAError.invalidResponse("لم يصل رد صحيح من GitHub.")
        }
        return (http.statusCode, data)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IPAError.invalidResponse("بيانات GitHub ليست بصيغة متوقعة.")
        }
        return value
    }

    private func expectSuccess(_ status: Int, _ data: Data,
                               stage: String, notFoundAdvice: String) throws {
        guard (200...299).contains(status) else {
            let responseMessage = (try? object(data)["message"] as? String) ?? "لا توجد تفاصيل إضافية"
            let advice: String
            switch status {
            case 401:
                advice = "رمز GitHub غير صالح أو انتهت صلاحيته. أنشئ رمزًا جديدًا واحفظه في إعدادات IPA109."
            case 403:
                advice = "تحقق من صلاحيات الرمز على مستودع IPA109: Contents وActions بصلاحية Read and write."
            case 404:
                advice = notFoundAdvice
            default:
                advice = "راجع إعدادات GitHub وجرّب مرة أخرى، أو صوّر اسم المرحلة ورقم الخطأ فقط."
            }
            throw IPAError.serverMessage("فشل اتصال GitHub في مرحلة: \(stage)\nرمز الخطأ: \(status) — \(responseMessage)\n\(advice)")
        }
    }

    func startBuild(project: AppProject) async throws -> BuildResult {
        guard !project.html.isEmpty else {
            throw IPAError.missingSettings("أنشئ التطبيق أو استورد HTML أولاً قبل التصدير.")
        }
        let sourceBranch = config.githubBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "main" : config.githubBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = "ipa109-build-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))
        let shortID = String(project.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))
        let tag = "ipa109-app-\(shortID)-\(UUID().uuidString.prefix(8).lowercased())"

        // Verify the repository is accessible to the token before changing anything.
        let (repoStatus, repoData) = try await call("")
        try expectSuccess(repoStatus, repoData,
                          stage: "الوصول إلى المستودع",
                          notFoundAdvice: "تأكد أن اسم الحساب \(owner) واسم المستودع \(repo) صحيحان، وأن Fine-grained Token يسمح بالوصول إلى هذا المستودع تحديدًا.")

        let (refStatus, refData) = try await call("/git/ref/heads/\(sourceBranch)")
        try expectSuccess(refStatus, refData,
                          stage: "قراءة الفرع \(sourceBranch)",
                          notFoundAdvice: "الفرع \(sourceBranch) غير موجود أو غير متاح. تحقق أن الفرع الأساسي هو main.")
        guard let refObject = try object(refData)["object"] as? [String: Any],
              let commitSHA = refObject["sha"] as? String else {
            throw IPAError.invalidResponse("تعذر قراءة رقم commit للفرع الأساسي.")
        }

        let templatePath = "/contents/GeneratedApp/Resources/webapp.html"
        let (templateStatus, templateData) = try await call(
            templatePath, query: [URLQueryItem(name: "ref", value: sourceBranch)]
        )
        try expectSuccess(templateStatus, templateData,
                          stage: "قراءة قالب التطبيق GeneratedApp/Resources/webapp.html",
                          notFoundAdvice: "الملف GeneratedApp/Resources/webapp.html غير موجود في جذر المستودع على الفرع \(sourceBranch). تأكد من مساره حرفيًا.")
        guard let oldSHA = try object(templateData)["sha"] as? String else {
            throw IPAError.invalidResponse("تعذر تحديد نسخة قالب التطبيق.")
        }

        let (workflowStatus, workflowData) = try await call("/actions/workflows/build-generated.yml")
        try expectSuccess(workflowStatus, workflowData,
                          stage: "العثور على مهمة build-generated.yml",
                          notFoundAdvice: "تأكد أن ملف .github/workflows/build-generated.yml موجود على الفرع الأساسي وأن Token لديه صلاحية Actions: Read and write.")
        if let state = (try? object(workflowData)["state"] as? String), state != "active" {
            throw IPAError.invalidResponse("مهمة build-generated.yml حالتها \(state). فعّلها من GitHub Actions أولاً.")
        }

        let (createStatus, createData) = try await call("/git/refs", method: "POST", body: [
            "ref": "refs/heads/\(branch)", "sha": commitSHA
        ])
        try expectSuccess(createStatus, createData,
                          stage: "إنشاء فرع مؤقت للتطبيق",
                          notFoundAdvice: "تعذر إنشاء الفرع. تأكد من أن Token مرتبط بمستودع \(repo) وصلاحية Contents: Read and write.")

        let (putStatus, putData) = try await call(templatePath, method: "PUT", body: [
            "message": "IPA109: build generated project \(shortID)",
            "content": Data(project.html.utf8).base64EncodedString(),
            "sha": oldSHA,
            "branch": branch
        ])
        try expectSuccess(putStatus, putData,
                          stage: "رفع كود HTML للتطبيق",
                          notFoundAdvice: "تعذر تعديل قالب التطبيق على الفرع الجديد. راجع صلاحية Contents ومسار GeneratedApp/Resources/webapp.html.")

        let (dispatchStatus, dispatchData) = try await call(
            "/actions/workflows/build-generated.yml/dispatches", method: "POST", body: [
                "ref": branch,
                "inputs": ["tag": tag, "project_id": shortID, "title": String(project.title.prefix(50))]
            ]
        )
        try expectSuccess(dispatchStatus, dispatchData,
                          stage: "تشغيل GitHub Actions لبناء IPA",
                          notFoundAdvice: "لم يتم العثور على مهمة البناء أو لم يُسمح بتشغيلها. راجع .github/workflows/build-generated.yml وصلاحية Actions: Read and write.")

        return BuildResult(tag: tag, releaseURL: "https://github.com/\(owner)/\(repo)/releases/tag/\(tag)")
    }

    func releaseIPA(tag: String) async throws -> String? {
        let (status, data) = try await call("/releases/tags/\(tag)")
        if status == 404 { return nil }
        try expectSuccess(status, data,
                          stage: "البحث عن ملف IPA النهائي",
                          notFoundAdvice: "لم يُنشأ إصدار GitHub لهذا المشروع بعد. افحص سجل المهمة في Actions.")
        guard let assets = try object(data)["assets"] as? [[String: Any]],
              let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".ipa") == true }),
              let url = asset["browser_download_url"] as? String else {
            return nil
        }
        return url
    }
}
