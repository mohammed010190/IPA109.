import SwiftUI
import WebKit

private enum Theme {
    static let background = Color(red: 0.038, green: 0.055, blue: 0.13)
    static let card = Color(red: 0.085, green: 0.10, blue: 0.21)
    static let blue = Color(red: 0.10, green: 0.77, blue: 0.99)
    static let purple = Color(red: 0.66, green: 0.36, blue: 0.99)
    static let primary = LinearGradient(colors: [blue, purple], startPoint: .leading, endPoint: .trailing)
}

@main
struct IPA109App: App {
    @StateObject private var store = ProjectStore()
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { ChatScreen(projectID: nil) }
                    .tabItem { Label("إنشاء", systemImage: "sparkles") }
                NavigationStack { CodeImportScreen() }
                    .tabItem { Label("من كود", systemImage: "chevron.left.forwardslash.chevron.right") }
                NavigationStack { ProjectsScreen() }
                    .tabItem { Label("مشاريعي", systemImage: "square.stack.3d.up") }
                NavigationStack { SettingsScreen() }
                    .tabItem { Label("الإعدادات", systemImage: "gearshape") }
            }
            .environmentObject(store)
            .tint(Theme.purple)
            .preferredColorScheme(.dark)
        }
    }
}

private struct TitleCard: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .trailing, spacing: 9) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(Theme.primary).font(.system(size: 30))
                Spacer()
                Text("IPA109")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.primary)
            }
            Text(title).font(.title2.bold()).frame(maxWidth: .infinity, alignment: .trailing)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.purple.opacity(0.4)))
    }
}

private struct ChatScreen: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var activeID: UUID?
    @State private var prompt = ""
    @State private var working = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showPreview = false
    @State private var showExport = false

    init(projectID: UUID?) { _activeID = State(initialValue: projectID) }

    private var current: AppProject? { store.projects.first(where: { $0.id == activeID }) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    TitleCard(title: current?.title ?? "من فكرتك إلى تطبيق", subtitle: "اكتب طلبك بالعربي. لغة التطبيق الناتج حسب اختيارك، حتى الإنجليزية.")
                    if let current = current {
                        ForEach(current.messages) { entry in
                            HStack {
                                if entry.isUser { Spacer(minLength: 40) }
                                Text(entry.text)
                                    .multilineTextAlignment(.trailing)
                                    .padding(13)
                                    .background(entry.isUser ? Theme.purple.opacity(0.33) : Theme.card,
                                                in: RoundedRectangle(cornerRadius: 17))
                                    .frame(maxWidth: .infinity, alignment: entry.isUser ? .trailing : .leading)
                                if !entry.isUser { Spacer(minLength: 40) }
                            }
                        }
                        if !current.html.isEmpty {
                            HStack(spacing: 10) {
                                Button { showPreview = true } label: {
                                    Label("معاينة التطبيق", systemImage: "eye")
                                }
                                .buttonStyle(.bordered)
                                Button { showExport = true } label: {
                                    Label("تصدير IPA", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(alignment: .trailing, spacing: 10) {
                            Label("مثال ١: اصنع تطبيق ملاحظات باللغة الإنجليزية", systemImage: "sparkle")
                            Label("مثال ٢: اصنع لعبة بالعربية", systemImage: "sparkle")
                            Label("مثال ٣: غيّر التصميم وأضف زر البحث", systemImage: "sparkle")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(16)
                    }
                    if working {
                        HStack {
                            ProgressView().tint(Theme.blue)
                            Text("Gemini يصنع التعديل...").foregroundStyle(.secondary)
                        }.padding()
                    }
                }
                .padding(15)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("صف تطبيقك أو اطلب تعديلًا...", text: $prompt, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .textInputAutocapitalization(.sentences)
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .frame(width: 46, height: 46)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .disabled(working || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(Theme.background)
        }
        .background(Theme.background)
        .navigationTitle("IPA109")
        .toolbar {
            if current != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { activeID = nil } label: { Image(systemName: "plus.circle") }
                }
            }
        }
        .sheet(isPresented: $showPreview) { PreviewScreen(html: current?.html ?? "") }
        .sheet(isPresented: $showExport) {
            if let id = activeID { ExportScreen(projectID: id) }
        }
        .alert("تعذر إنشاء التطبيق", isPresented: $showError) {
            Button("حسنًا", role: .cancel) {}
        } message: { Text(errorMessage) }
    }

    private func send() {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !working else { return }
        let id = activeID ?? store.create()
        activeID = id
        let previousHTML = store.projects.first(where: { $0.id == id })?.html ?? ""
        store.mutate(id) { $0.messages.append(ChatEntry(text: request, isUser: true)) }
        prompt = ""
        working = true
        Task {
            do {
                let result = try await GeminiClient().generate(request: request, existingHTML: previousHTML, key: UserConfig().geminiKey)
                store.mutate(id) { project in
                    project.title = result.title
                    project.html = result.html
                    project.buildTag = nil
                    project.ipaURL = nil
                    project.messages.append(ChatEntry(text: result.message, isUser: false))
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                store.mutate(id) { $0.messages.append(ChatEntry(text: "تعذر التنفيذ. تستطيع إعادة المحاولة.", isUser: false)) }
            }
            working = false
        }
    }
}

private struct ProjectsScreen: View {
    @EnvironmentObject private var store: ProjectStore
    var body: some View {
        List {
            Section {
                TitleCard(title: "مشاريعي", subtitle: "كل تطبيقاتك المحفوظة هنا، ويمكنك تعديلها في أي وقت.")
                    .listRowBackground(Color.clear)
            }
            ForEach(store.projects) { project in
                NavigationLink {
                    ChatScreen(projectID: project.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "app.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.primary)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(project.title).font(.headline)
                            Text(project.html.isEmpty ? "بانتظار الإنشاء" : "قابل للمعاينة والتعديل")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                }
            }
            .onDelete(perform: store.delete)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("مشاريعي")
    }
}

private struct PreviewScreen: View {
    let html: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            HTMLPreview(html: html)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("معاينة التطبيق")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("إغلاق") { dismiss() } } }
        }
    }
}

private struct HTMLPreview: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.loadHTMLString(html, baseURL: nil)
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // The sheet is reopened when the HTML changes; avoid resetting page state while interacting.
    }
}

private struct ExportScreen: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    @State private var working = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var status = ""
    private var project: AppProject? { store.projects.first(where: { $0.id == projectID }) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .trailing, spacing: 18) {
                TitleCard(title: "تصدير IPA", subtitle: "نبني نسخة iOS غير موقعة على GitHub ثم تحملها إلى SideStore.")
                if let project = project {
                    Text(project.title).font(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if let url = project.ipaURL, let link = URL(string: url) {
                        Link(destination: link) {
                            Label("تحميل ملف IPA", systemImage: "arrow.down.doc")
                                .frame(maxWidth: .infinity).padding()
                                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14))
                        }
                        Text("بعد التحميل، افتح الملف باستخدام SideStore.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let tag = project.buildTag {
                        Text("بدأ البناء: \(tag)").font(.caption).textSelection(.enabled)
                        Button(action: check) { Label("تحقق من جاهزية IPA", systemImage: "arrow.clockwise") }
                            .buttonStyle(.borderedProminent)
                        Text("إذا لم يكتمل بعد، افتح GitHub Actions لمراجعة حالة المهمة.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(action: build) {
                        Label("\(project.buildTag == nil ? "ابدأ بناء IPA" : "بناء نسخة جديدة")", systemImage: "hammer.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working)
                    if working { ProgressView("جارٍ الاتصال بـ GitHub...") }
                    if !status.isEmpty { Text(status).foregroundStyle(.secondary).font(.footnote) }
                    Text("ملاحظة: التطبيق الناتج يحتوي على واجهة HTML/JavaScript داخل غلاف iOS حقيقي. ميزات iOS الأصلية مثل الإشعارات وiCloud تحتاج تطويرًا إضافيًا. إن استخدمت مستودعًا عامًا فالكود الناتج سيكون عامًا.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
            .background(Theme.background)
            .navigationTitle("البناء والتصدير")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("إغلاق") { dismiss() } } }
            .alert("حدث خطأ", isPresented: $showError) { Button("حسنًا", role: .cancel) {} } message: { Text(errorMessage) }
        }
    }

    private func build() {
        guard let project = project else { return }
        working = true
        status = "نجهز نسخة التطبيق للبناء..."
        Task {
            do {
                let result = try await GitHubClient(config: UserConfig()).startBuild(project: project)
                store.mutate(projectID) { $0.buildTag = result.tag; $0.ipaURL = nil }
                status = "تم إرسال المهمة. اضغط تحقق بعد انتهاء البناء في GitHub."
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            working = false
        }
    }

    private func check() {
        guard let tag = project?.buildTag else { return }
        working = true
        Task {
            do {
                if let url = try await GitHubClient(config: UserConfig()).releaseIPA(tag: tag) {
                    store.mutate(projectID) { $0.ipaURL = url }
                    status = "النسخة جاهزة للتنزيل."
                } else {
                    status = "لم ينته البناء بعد، أو لم يُنشأ الإصدار. راجع GitHub Actions للتفاصيل."
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            working = false
        }
    }
}

private struct SettingsScreen: View {
    @State private var geminiKey = ""
    @State private var githubToken = ""
    @State private var owner = ""
    @State private var repo = ""
    @State private var branch = "main"
    @State private var didSave = false
    var body: some View {
        Form {
            Section("Gemini — الذكاء الاصطناعي") {
                SecureField("Gemini API Key", text: $geminiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Link("احصل على مفتاح Gemini", destination: URL(string: "https://aistudio.google.com/api-keys")!)
                Text("مفتاحك محفوظ في Keychain على آيفونك، وليس مضمنًا في التطبيق.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("GitHub — بناء ملف IPA") {
                TextField("اسم حساب GitHub", text: $owner)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("اسم المستودع، مثل IPA109", text: $repo)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("الفرع الأساسي", text: $branch)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Fine-grained GitHub Token", text: $githubToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("أنشئ مستودعًا من ملفات المشروع المرفقة. امنح الرمز صلاحيات Contents وActions للقراءة والكتابة على هذا المستودع فقط.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("إذا كان المستودع عامًا، ستكون ملفات التطبيقات التي تُرسل للبناء مرئية للآخرين.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Section {
                Button {
                    SecretStore.set(geminiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "gemini")
                    SecretStore.set(githubToken.trimmingCharacters(in: .whitespacesAndNewlines), for: "github")
                    UserDefaults.standard.set(owner.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "githubOwner")
                    UserDefaults.standard.set(repo.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "githubRepo")
                    UserDefaults.standard.set(branch.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "githubBranch")
                    didSave = true
                } label: {
                    Label("حفظ الإعدادات", systemImage: "checkmark.shield.fill")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("الإعدادات")
        .onAppear {
            geminiKey = SecretStore.get("gemini")
            githubToken = SecretStore.get("github")
            owner = UserDefaults.standard.string(forKey: "githubOwner") ?? ""
            repo = UserDefaults.standard.string(forKey: "githubRepo") ?? ""
            branch = UserDefaults.standard.string(forKey: "githubBranch") ?? "main"
        }
        .alert("تم حفظ الإعدادات", isPresented: $didSave) { Button("تمام", role: .cancel) {} }
    }
}
