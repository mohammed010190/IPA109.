import Foundation

struct GeminiClient {
    func generate(request: String, existingHTML: String, key: String) async throws -> AIResult {
        guard !key.isEmpty else {
            throw IPAError.missingSettings("أضف مفتاح Gemini من الإعدادات أولاً.")
        }

        let prompt = """
        You are an expert developer creating a fully functional, offline-first mobile web app that will be bundled inside a REAL iOS WKWebView app and exported as an IPA.

        Respond ONLY in JSON with keys: title, html, message. The 'html' property must be a COMPLETE standalone single HTML file with inline CSS and JavaScript. No external assets, CDN, APIs or libraries. Fully responsive, touch friendly, no placeholders or fake working buttons. Implement only features realistic in a standalone web app. Use localStorage for persistence where useful. Favor safe DOM manipulation over injecting user content. No markdown fences.

        IMPORTANT LANGUAGE RULE: The IPA109 builder shell is Arabic, but the GENERATED APP's language must follow the user's request exactly. If the user asks for English, EVERYTHING in the generated app should be in English, including labels and buttons. If they ask for Arabic, use Arabic. If they ask for both, support both. If editing, preserve the existing generated app language unless the user explicitly changes it.

        The 'message' is a brief confirmation in Arabic describing real changes. The 'title' is a brief suitable app title.

        User request: \(request)

        \(existingHTML.isEmpty ? "This is a new app. Generate it." : "Edit the existing app while keeping existing features and data: \n" + String(existingHTML.prefix(28000)))
        """

        let requestJSON: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": prompt]]
            ]],
            "generationConfig": ["responseMimeType": "application/json"]
        ]
        let payload = try JSONSerialization.data(withJSONObject: requestJSON)
        let models = ["gemini-3.8-flash", "gemini-3.5-flash-lite"]

        for (modelIndex, model) in models.enumerated() {
            for attempt in 0..<3 {
                try Task.checkCancellation()
                let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
                var http = URLRequest(url: url)
                http.httpMethod = "POST"
                http.timeoutInterval = 100
                http.addValue("application/json", forHTTPHeaderField: "Content-Type")
                http.addValue(key, forHTTPHeaderField: "x-goog-api-key")
                http.httpBody = payload

                let data: Data
                let response: URLResponse
                do {
                    (data, response) = try await URLSession.shared.data(for: http)
                } catch {
                    if attempt < 2 {
                        try await Task.sleep(nanoseconds: UInt64(2 << attempt) * 1_000_000_000)
                        continue
                    }
                    if modelIndex == models.count - 1 {
                        throw IPAError.serverMessage("تعذر الاتصال بـGemini. تحقق من الإنترنت ثم حاول لاحقًا.")
                    }
                    break
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw IPAError.invalidResponse("تعذر الاتصال بـGemini.")
                }

                switch httpResponse.statusCode {
                case 200...299:
                    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let candidates = root["candidates"] as? [[String: Any]],
                          let content = candidates.first?["content"] as? [String: Any],
                          let parts = content["parts"] as? [[String: Any]],
                          let answer = parts.compactMap({ $0["text"] as? String }).first,
                          let jsonData = answer.data(using: .utf8) else {
                        throw IPAError.invalidResponse("Gemini لم يرجع مشروعًا صالحًا. حاول مرة ثانية.")
                    }

                    let result = try JSONDecoder().decode(AIResult.self, from: jsonData)
                    let html = result.html.lowercased()
                    guard html.contains("<html") || html.contains("<!doctype") else {
                        throw IPAError.invalidResponse("الذكاء الاصطناعي لم يُرجع ملف HTML صالحًا.")
                    }
                    return result

                case 503, 500, 502, 504:
                    if attempt < 2 {
                        try await Task.sleep(nanoseconds: UInt64(2 << attempt) * 1_000_000_000)
                        continue
                    }
                    break // Try the backup model.

                case 404:
                    break // This model is not available to this API key.

                case 429:
                    throw IPAError.serverMessage("وصلت إلى حد الطلبات المتاح لحساب Gemini. راجع حصتك المجانية وحاول بعد تجددها.")

                case 400, 401, 403:
                    throw IPAError.serverMessage("رفض Gemini الطلب (\(httpResponse.statusCode)). راجع مفتاح API وصلاحيات النموذج.")

                default:
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw IPAError.serverMessage("Gemini (\(httpResponse.statusCode)): \(String(body.prefix(300)))")
                }
                // Current model failed even after retries. Switch to backup.
                break
            }
        }
        throw IPAError.serverMessage("خوادم Gemini مشغولة أو النماذج غير متاحة لمفتاحك الآن. جرّب لاحقًا أو استخدم تبويب «من كود».")
    }
}
