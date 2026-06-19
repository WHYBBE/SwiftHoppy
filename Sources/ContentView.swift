import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SSHConnectionStore
    @EnvironmentObject private var preferences: AppPreferencesStore
    @State private var selectedID: SSHConnection.ID?
    @State private var errorMessage = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(store.connections) { connection in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(connection.displayName)
                            .font(.headline)
                        Text(connection.host)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .tag(connection.id)
                }
                .onDelete(perform: deleteConnections)
            }
            .navigationTitle("SSH Records")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedID = store.addConnection()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let connection = selectedConnection {
                ConnectionDetailView(
                    connection: connection,
                    installedApps: preferences.installedApps,
                    onSave: { store.update($0) },
                    onDelete: {
                        let deletedID = connection.id
                        store.delete(id: deletedID)
                        if selectedID == deletedID {
                            selectedID = store.connections.first?.id
                        }
                    },
                    onOpen: openConnection,
                    errorMessage: errorMessage,
                    onDismissError: { errorMessage = "" }
                )
                .id(connection.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("No Selection")
                        .font(.title3)
                    Text("请选择或新建一条 SSH 记录。")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedID == nil {
                selectedID = store.connections.first?.id
            }
        }
    }

    private var selectedConnection: SSHConnection? {
        guard let selectedID else { return nil }
        return store.connections.first(where: { $0.id == selectedID })
    }

    private func deleteConnections(at offsets: IndexSet) {
        let ids = offsets.compactMap { index in
            store.connections.indices.contains(index) ? store.connections[index].id : nil
        }
        store.delete(at: offsets)
        if let selectedID, ids.contains(selectedID) {
            self.selectedID = store.connections.first?.id
        }
    }

    private func openConnection(_ connection: SSHConnection) {
        guard let url = connection.sshURL else {
            errorMessage = "SSH 地址无效，请检查主机、端口和用户名。"
            return
        }

        let appPath = connection.preferredAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if appPath.isEmpty {
            NSWorkspace.shared.open(url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: appPath), configuration: configuration) { _, error in
            if let error {
                errorMessage = "打开 SSH 连接失败：\(error.localizedDescription)"
            }
        }
    }
}

struct ConnectionDetailView: View {
    @State private var draft: SSHConnection
    @State private var isFetchingSystemInfo = false
    @State private var fetchErrorMessage = ""
    let installedApps: [InstalledTerminalApp]
    let onSave: (SSHConnection) -> Void
    let onDelete: () -> Void
    let onOpen: (SSHConnection) -> Void
    let errorMessage: String
    let onDismissError: () -> Void

    init(
        connection: SSHConnection,
        installedApps: [InstalledTerminalApp],
        onSave: @escaping (SSHConnection) -> Void,
        onDelete: @escaping () -> Void,
        onOpen: @escaping (SSHConnection) -> Void,
        errorMessage: String,
        onDismissError: @escaping () -> Void
    ) {
        self._draft = State(initialValue: connection)
        self.installedApps = installedApps
        self.onSave = onSave
        self.onDelete = onDelete
        self.onOpen = onOpen
        self.errorMessage = errorMessage
        self.onDismissError = onDismissError
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Form {
                Section("Connection") {
                    TextField("Name", text: $draft.name)
                    TextField("Host", text: $draft.host)
                    TextField("Username", text: $draft.username)
                    Stepper(value: $draft.port, in: 1...65535) {
                        Text("Port: \(draft.port)")
                    }
                }

                Section("Open With") {
                    Picker("Installed Apps", selection: $draft.preferredAppPath) {
                        Text("System Default").tag("")
                        ForEach(installedApps) { app in
                            Text(app.name).tag(app.path)
                        }
                    }

                    if !draft.preferredAppPath.isEmpty {
                        Text(draft.preferredAppPath)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack {
                        Button("Choose Application") {
                            chooseApplication()
                        }

                        if !draft.preferredAppPath.isEmpty {
                            Button("Clear") {
                                draft.preferredAppPath = ""
                            }
                        }
                    }

                    Text("默认使用系统应用。可在设置中检测并缓存已安装终端，或手动选择任意 .app。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 220)
                }

                Section {
                    HStack {
                        Button("Save") {
                            onSave(draft)
                        }
                        .keyboardShortcut("s", modifiers: [.command])

                        Button("Open SSH") {
                            onOpen(draft)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Delete", role: .destructive) {
                            onDelete()
                        }

                        Spacer()

                        if let url = draft.sshURL {
                            Text(url.absoluteString)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minWidth: 420)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("System History")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    Button(isFetchingSystemInfo ? "Reading via SSH..." : "Read via SSH") {
                        refreshRemoteSystemInfo()
                    }
                    .disabled(isFetchingSystemInfo)

                    Button("Add Manual Entry") {
                        draft.systemInfoHistory.insert(SystemInfoSnapshot(), at: 0)
                    }
                }

                Text("每次 SSH 读取都会追加一条历史，也可手动补录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if draft.systemInfoHistory.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("暂无系统信息历史。")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach($draft.systemInfoHistory) { $snapshot in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(snapshot.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline)
                                    Spacer()
                                    Button("Delete") {
                                        deleteSnapshot(id: snapshot.id)
                                    }
                                    .buttonStyle(.link)
                                }

                                TextField("Kernel Version", text: $snapshot.kernelVersion)
                                TextField("Last Update Info", text: $snapshot.updateInfo)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding()
        .navigationTitle(draft.displayName)
        .onChange(of: draft) { newValue in
            onSave(newValue)
        }
        .alert("操作失败", isPresented: Binding(
            get: { !errorMessage.isEmpty || !fetchErrorMessage.isEmpty },
            set: { isPresented in
                if !isPresented {
                    onDismissError()
                    fetchErrorMessage = ""
                }
            }
        )) {
            Button("OK") {
                onDismissError()
                fetchErrorMessage = ""
            }
        } message: {
            Text(fetchErrorMessage.isEmpty ? errorMessage : fetchErrorMessage)
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK {
            draft.preferredAppPath = panel.url?.path ?? ""
        }
    }

    private func refreshRemoteSystemInfo() {
        let snapshot = draft
        isFetchingSystemInfo = true
        fetchErrorMessage = ""

        Task {
            do {
                let info = try await RemoteSystemInfoService.fetch(for: snapshot)
                await MainActor.run {
                    draft.systemInfoHistory.insert(
                        SystemInfoSnapshot(
                            kernelVersion: info.kernelVersion,
                            updateInfo: info.updateInfo,
                            recordedAt: info.recordedAt
                        ),
                        at: 0
                    )
                    isFetchingSystemInfo = false
                }
            } catch {
                await MainActor.run {
                    fetchErrorMessage = error.localizedDescription
                    isFetchingSystemInfo = false
                }
            }
        }
    }

    private func deleteSnapshot(id: SystemInfoSnapshot.ID) {
        draft.systemInfoHistory.removeAll { $0.id == id }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    var body: some View {
        Form {
            Section("Terminal Apps") {
                Button("Detect Installed Terminal Apps") {
                    preferences.refreshInstalledApps()
                }

                if let lastScannedAt = preferences.lastScannedAt {
                    Text("Last scanned: \(lastScannedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("尚未检测，默认直接使用系统应用打开 SSH。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if preferences.installedApps.isEmpty {
                    Text("暂无缓存结果。点击上方按钮按需检测一次。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preferences.installedApps) { app in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                            Text(app.path)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 560)
    }
}
