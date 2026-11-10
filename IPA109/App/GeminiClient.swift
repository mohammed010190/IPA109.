import Foundation

struct GeminiClient {
    func generate(request: String, existingHTML: String, key: String) async throws -> AIResult {
        guard !key.isEmpty else { throw IPAError.missingSettings("أضف مفتاح Gemini المجاني من الإعدادات أولاً.") }
        let prompt = """
        You are an expert developer creating a fully functional, offline-first mobile web app that will be bundled inside a REAL iOS WKWebView app and exported as an IPA.
        Respond ONLY in JSON with keys: title, html, message. The 'html' property must be a COMPLETE standalone single HTML file with inline CSS and JavaScript. No external assets, CDN, APIs or libraries. Fully responsive, touch friendly, no placeholders or fake working buttons. Implement only features realistic in a standalone web app. Use localStorage for persistence where useful. Favor safe DOM manipulation over injecting user content. No markdown fences.
        IMPORTANT LANGUAGE RULE: The IPA109 builder shell is Arabic, but the GENERATED APP's language must follow the user's request exactly. If the user asks for English, EVERYTHING in the generated app should be in English, including labels and buttons. If they ask for Arabic, use Arabic. If they ask for both, support both. If editing, preserve the existing generated app language unless the user explicitly changes it.
        The 'message' is a brief confirmation in Arabic describing real changes. The 'title' is a brief suitable app title.
        User request: \(request)
        \(existingHTML.isEmpty ? "This is a new app. Generate it." : "Edit the existing app while keeping existing features and data: \n" + String(existingHTML.prefix(28000)))
        """
        let requestJSON: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0.35]
        ]
let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")!
        var http = URLRequest(url: url)
        http.httpMethod = "POST"
        http.timeoutInterval = 100
        http.addValue("application/json", forHTTPHeaderField: "Content-Type")
        http.addValue(key, forHTTPHeaderField: "x-goog-api-key")
        http.httpBody = try JSONSerialization.data(withJSONObject: requestJSON)
        let (data, response) = try await URLSession.shared.data(for: http)
        guard let httpResponse = response as? HTTPURLResponse else { throw IPAError.invalidResponse("تعذر الاتصال بـGemini.") }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw IPAError.serverMessage("Gemini (\(httpResponse.statusCode)): \(String(body.prefix(360)))")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let answer = parts.compactMap({ $0["text"] as? String }).first,
              let jsonData = answer.data(using: .utf8) else {
            throw IPAError.invalidResponse("Gemini لم يرجع مشروعًا صالحًا. حاول مرة ثانية.")
        }
        let result = try JSONDecoder().decode(AIResult.self, from: jsonData)
        guard result.html.lowercased().contains("<html") || result.html.lowercased().contains("<!doctype") else {
            throw IPAError.invalidResponse("الذكاء الاصطناعي لم يُرجع ملف تطبيق HTML صالحًا.")
        }
        return result
    }
}
