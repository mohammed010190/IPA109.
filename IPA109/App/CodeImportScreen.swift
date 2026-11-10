import SwiftUI
import WebKit
import UniformTypeIdentifiers

// Import a self-contained HTML app without calling Gemini.
// This view reuses the existing ProjectStore, preview and GitHub export flows.
struct CodeImportScreen: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var appTitle = ""
    @State private var html = ""
    @State private var isPickingFile = false
    @State private var isPreviewing = false
    @State private var showSaved = false
    @State private var errorText = ""
    @State private var showError = false

    private var validHTML: Bool {
        let text = html.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.contains("<html") || text.contains("<!doctype html")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 16) {
                VStack(alignment: .trailing, spacing: 8) {
                    Label("إنشاء من كود", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.title2.bold())
                    Text("الصق كود HTML كاملًا من أي مصدر أو استورد ملف HTML، ثم احفظ التطبيق وصدّره من مشاريعي. لا تحتاج Gemini لهذه الطريقة.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                TextField("اسم التطبيق", text: $appTitle)
                    .textInputAutocapitalization(.words)
                    .padding(13)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                HStack {
                    Button {
                        isPickingFile = true
                    } label: {
                        Label("استيراد ملف HTML", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Text("كود التطبيق")
                        .font(.headline)
                }

                TextEditor(text: $html)
                    .font(.system(size: 13, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 270)
                    .scrollContentBackground(.hidden)
                    .padding(9)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.purple.opacity(0.4)))

                HStack(spacing: 10) {
                    Button {
                        isPreviewing = true
                    } label: {
                        Label("معاينة", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!validHTML)

                    Button(action: saveProject) {
                        Label("حفظ كمشروع", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!validHTML)
                }

                Text("يدعم هذا الخيار ملفات HTML كاملة مع CSS وJavaScript داخلها. كود Swift أو Python أو مشروع ZIP لا يتحول تلقائيًا هنا إلى IPA. عند الحفظ افتح «مشاريعي» ثم التطبيق، واضغط «تصدير IPA».")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(16)
        }
        .navigationTitle("IPA109 | من كود")
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.html, .plainText]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    guard let contents = String(data: data, encoding: .utf8) else {
                        throw ImportError.notUTF8
                    }
                    html = contents
                    if appTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appTitle = url.deletingPathExtension().lastPathComponent
                    }
                } catch {
                    errorText = "تعذر قراءة الملف. تأكد أنه HTML محفوظ بترميز UTF-8.\n\(error.localizedDescription)"
                    showError = true
                }
            case .failure(let error):
                errorText = error.localizedDescription
                showError = true
            }
        }
        .sheet(isPresented: $isPreviewing) {
            NavigationStack {
                ImportedHTMLPreview(html: html)
                    .navigationTitle("معاينة الكود")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("إغلاق") { isPreviewing = false }
                        }
                    }
            }
        }
        .alert("تم حفظ المشروع", isPresented: $showSaved) {
            Button("تمام", role: .cancel) {}
        } message: {
            Text("افتح تبويب «مشاريعي» للمعاينة والتعديل وتصدير IPA.")
        }
        .alert("تعذر استيراد الكود", isPresented: $showError) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(errorText)
        }
    }

    private func saveProject() {
        guard validHTML else { return }
        let title = appTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = store.create()
        store.mutate(projectID) { project in
            project.title = title.isEmpty ? "تطبيق من كود" : title
            project.html = html
            project.messages = [ChatEntry(text: "تم استيراد كود HTML جاهز دون استخدام Gemini.", isUser: false)]
            project.buildTag = nil
            project.ipaURL = nil
        }
        showSaved = true
    }
}

private enum ImportError: LocalizedError {
    case notUTF8
    var errorDescription: String? { "الملف ليس UTF-8" }
}

private struct ImportedHTMLPreview: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.isOpaque = false
        view.backgroundColor = .black
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
