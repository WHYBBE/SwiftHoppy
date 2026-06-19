import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SSHConnectionStore
    @EnvironmentObject private var preferences: AppPreferencesStore
    @State private var selectedID: SSHConnection.ID?
    @State private var errorMessage = ""

    private func t(_ chinese: String, _ english: String) -> String {
        preferences.text(chinese, english)
    }

    private var selectableConnectionID: Binding<SSHConnection.ID?> {
        Binding(
            get: { selectedID },
            set: { newValue in
                guard let newValue else {
                    selectedID = nil
                    return
                }
                if let connection = store.connections.first(where: { $0.id == newValue }), !connection.isSeparator {
                    selectedID = newValue
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea()

                Group {
                    if store.connections.isEmpty {
                        sidebarEmptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 10) {
                            HStack {
                                Label(t("排序", "Sort"), systemImage: "arrow.up.arrow.down")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 8)

                                Menu {
                                    Button(t("手动", "Manual")) {
                                        preferences.setConnectionSortMode(.manual)
                                    }
                                    Button(t("名称", "Name")) {
                                        preferences.setConnectionSortMode(.name)
                                    }
                                    Button("IP") {
                                        preferences.setConnectionSortMode(.ip)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(sortModeLabel)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption2)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.primary.opacity(0.06))
                                    )
                                }
                                .menuStyle(.borderlessButton)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                            List(selection: selectableConnectionID) {
                                ForEach(sortedConnections) { connection in
                                    if connection.isSeparator {
                                        SidebarSeparatorRow()
                                            .contextMenu {
                                                Button(t("删除分割线", "Delete Divider"), role: .destructive) {
                                                    deleteConnection(id: connection.id)
                                                }
                                            }
                                    } else {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(connection.displayName.isEmpty ? connection.host : connection.displayName)
                                                .font(.headline)
                                                .lineLimit(1)

                                            Text(connection.host)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)

                                            if let latest = connection.latestSystemInfo,
                                               !latest.kernelVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                Text(latest.kernelVersion)
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                        .tag(connection.id)
                                    }
                                }
                                .onDelete(perform: deleteConnections)
                                .onMove(perform: preferences.connectionSortMode == .manual ? moveConnections : nil)
                            }
                            .listStyle(.sidebar)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                        }
                    }
                }
            }
            .navigationTitle(t("SSH 记录", "SSH Records"))
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 320)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedID = store.addConnection()
                    } label: {
                        Label(t("新增", "Add"), systemImage: "plus")
                    }
                }

                ToolbarItem {
                    if preferences.connectionSortMode == .manual {
                        Button {
                            selectedID = store.addSeparator()
                        } label: {
                            Label(t("新增分割线", "Add Divider"), systemImage: "line.3.horizontal")
                        }
                    }
                }
            }
        } detail: {
            if let connection = selectedConnection, !connection.isSeparator {
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
                detailEmptyState
            }
        }
        .onAppear {
            if selectedID == nil {
                selectedID = store.connections.first?.id
            }
        }
    }

    private var sidebarEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text(t("还没有连接记录", "No Connections Yet"))
                .font(.title3.weight(.semibold))
            Text(t("点击右上角新增，创建第一条 SSH 记录。", "Click Add in the top-right corner to create your first SSH record."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailEmptyState: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "server.rack")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(t("未选择记录", "No Selection"))
                    .font(.title2.weight(.semibold))
                Text(t("请选择左侧连接，或新建一条 SSH 记录开始管理。", "Pick a connection from the sidebar, or create a new SSH record to get started."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
    }

    private var selectedConnection: SSHConnection? {
        guard let selectedID else { return nil }
        return store.connections.first(where: { $0.id == selectedID })
    }

    private var sortedConnections: [SSHConnection] {
        switch preferences.connectionSortMode {
        case .manual:
            return store.connections.sorted {
                if $0.manualOrder == $1.manualOrder {
                    return $0.createdAt < $1.createdAt
                }
                return $0.manualOrder < $1.manualOrder
            }
        case .name:
            return store.connections.filter { !$0.isSeparator }.sorted {
                let left = $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let right = $1.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                return left.localizedStandardCompare(right) == .orderedAscending
            }
        case .ip:
            return store.connections.filter { !$0.isSeparator }.sorted { compareHosts($0.host, $1.host) }
        }
    }

    private var sortModeLabel: String {
        switch preferences.connectionSortMode {
        case .manual:
            return t("手动", "Manual")
        case .name:
            return t("名称", "Name")
        case .ip:
            return "IP"
        }
    }

    private func deleteConnections(at offsets: IndexSet) {
        let ids = offsets.compactMap { index in
            sortedConnections.indices.contains(index) ? sortedConnections[index].id : nil
        }
        store.connections.removeAll { ids.contains($0.id) }
        if let selectedID, ids.contains(selectedID) {
            self.selectedID = store.connections.first?.id
        }
    }

    private func deleteConnection(id: SSHConnection.ID) {
        store.delete(id: id)
        if selectedID == id {
            selectedID = store.connections.first(where: { !$0.isSeparator })?.id
        }
    }

    private func moveConnections(from source: IndexSet, to destination: Int) {
        guard preferences.connectionSortMode == .manual else { return }
        store.moveManually(from: source, to: destination)
    }

    private func compareHosts(_ lhs: String, _ rhs: String) -> Bool {
        let leftIP = ipv4Components(lhs)
        let rightIP = ipv4Components(rhs)

        if let leftIP, let rightIP {
            return leftIP.lexicographicallyPrecedes(rightIP)
        }
        if leftIP != nil { return true }
        if rightIP != nil { return false }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private func ipv4Components(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == 4, values.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return values
    }

    private func openConnection(_ connection: SSHConnection) {
        guard let url = connection.sshURL else {
            errorMessage = t("SSH 地址无效，请检查主机、端口和用户名。", "Invalid SSH address. Check host, port, and username.")
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
                errorMessage = "\(t("打开 SSH 连接失败", "Failed to open SSH connection"))：\(error.localizedDescription)"
            }
        }
    }
}

struct ConnectionDetailView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
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

    private func t(_ chinese: String, _ english: String) -> String {
        preferences.text(chinese, english)
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()

            VStack(spacing: 18) {
                detailHero

                HStack(alignment: .top, spacing: 18) {
                    ScrollView {
                        VStack(spacing: 16) {
                            detailCard(title: t("连接信息", "Connection"), icon: "network") {
                                VStack(spacing: 12) {
                                    modernField(title: t("名称", "Name")) {
                                        TextField(t("名称", "Name"), text: $draft.name)
                                    }
                                    modernField(title: t("主机", "Host")) {
                                        TextField(t("主机", "Host"), text: $draft.host)
                                    }
                                    modernField(title: t("用户名", "Username")) {
                                        TextField(t("用户名", "Username"), text: $draft.username)
                                    }
                                    modernField(title: t("端口", "Port")) {
                                        HStack(spacing: 10) {
                                            TextField(
                                                t("端口", "Port"),
                                                value: $draft.port,
                                                format: .number
                                            )
                                            .textFieldStyle(.plain)

                                            Stepper("", value: $draft.port, in: 1...65535)
                                                .labelsHidden()
                                        }
                                    }
                                }
                            }

                            detailCard(title: t("打开方式", "Open With"), icon: "app.connected.to.app.below.fill") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Picker(t("已安装应用", "Installed Apps"), selection: $draft.preferredAppPath) {
                                        Text(t("系统默认", "System Default")).tag("")
                                        ForEach(installedApps) { app in
                                            Text(app.name).tag(app.path)
                                        }
                                    }
                                    .labelsHidden()

                                    if !draft.preferredAppPath.isEmpty {
                                        Text(draft.preferredAppPath)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    HStack {
                                        Button(t("选择应用", "Choose Application")) {
                                            chooseApplication()
                                        }

                                        if !draft.preferredAppPath.isEmpty {
                                            Button(t("清除", "Clear")) {
                                                draft.preferredAppPath = ""
                                            }
                                        }
                                    }

                                    Text(t("默认使用系统应用。可在设置中检测并缓存已安装终端，或手动选择任意 .app。", "Uses the system app by default. You can detect installed terminal apps in Settings or choose any .app manually."))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            detailCard(title: t("备注", "Notes"), icon: "note.text") {
                                TextEditor(text: $draft.notes)
                                    .font(.body)
                                    .frame(minHeight: 220)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.primary.opacity(0.04))
                                    )
                            }
                        }
                    }
                    .frame(minWidth: 320, idealWidth: 420, maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 16) {
                        detailCard(title: t("系统历史", "System History"), icon: "clock.arrow.circlepath") {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Button(isFetchingSystemInfo ? t("正在通过 SSH 读取...", "Reading via SSH...") : t("通过 SSH 读取", "Read via SSH")) {
                                        refreshRemoteSystemInfo()
                                    }
                                    .disabled(isFetchingSystemInfo)

                                    Button(t("手动新增", "Add Manual Entry")) {
                                        draft.systemInfoHistory.insert(SystemInfoSnapshot(), at: 0)
                                    }
                                }

                                Text(t("每次 SSH 读取都会追加一条历史，也可手动补录。", "Each SSH read adds a history item, and you can also add entries manually."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                if draft.systemInfoHistory.isEmpty {
                                    VStack(spacing: 10) {
                                        Image(systemName: "clock.badge.questionmark")
                                            .font(.system(size: 28, weight: .medium))
                                            .foregroundStyle(.secondary)
                                        Text(t("暂无系统信息历史。", "No system history yet."))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 240)
                                } else {
                                    ScrollView {
                                        VStack(spacing: 12) {
                                            ForEach($draft.systemInfoHistory) { $snapshot in
                                                snapshotCard(snapshot: $snapshot)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(20)
        }
        .navigationTitle(draft.displayName)
        .onChange(of: draft) { newValue in
            onSave(newValue)
        }
        .alert(t("操作失败", "Operation Failed"), isPresented: Binding(
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

    private var detailHero: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                Image(systemName: "terminal.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.displayName.isEmpty ? draft.host : draft.displayName)
                    .font(.largeTitle.weight(.bold))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Label(draft.host.isEmpty ? t("未填写主机", "No host") : draft.host, systemImage: "server.rack")
                        Label("\(t("端口", "Port")) \(draft.port)", systemImage: "shippingbox")
                        if let latest = draft.latestSystemInfo {
                            Label(latest.recordedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            if !latest.uptimeInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Label(latest.uptimeInfo, systemImage: "timer")
                            }
                        }
                    }

                    if let url = draft.sshURL {
                        Label(url.absoluteString, systemImage: "link")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(t("打开 SSH", "Open SSH")) {
                    onOpen(draft)
                }
                .buttonStyle(.borderedProminent)

                Button(t("删除", "Delete"), role: .destructive) {
                    onDelete()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private func detailCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)
    }

    private func modernField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        }
    }

    private func snapshotCard(snapshot: Binding<SystemInfoSnapshot>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snapshot.wrappedValue.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(t("删除", "Delete")) {
                    deleteSnapshot(id: snapshot.wrappedValue.id)
                }
                .buttonStyle(.link)
            }

            modernField(title: t("内核版本", "Kernel Version")) {
                TextField(t("内核版本", "Kernel Version"), text: snapshot.kernelVersion)
            }

            modernField(title: t("最后更新信息", "Last Update Info")) {
                TextField(t("最后更新信息", "Last Update Info"), text: snapshot.updateInfo)
            }

            if !snapshot.wrappedValue.uptimeInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                modernField(title: t("运行时间", "Uptime")) {
                    TextField(t("运行时间", "Uptime"), text: snapshot.uptimeInfo)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
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
                            uptimeInfo: info.uptimeInfo,
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
    @EnvironmentObject private var store: SSHConnectionStore
    @EnvironmentObject private var preferences: AppPreferencesStore
    @State private var settingsErrorMessage = ""
    @State private var showClearConfirmation = false

    private func t(_ chinese: String, _ english: String) -> String {
        preferences.text(chinese, english)
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(t("设置", "Settings"))
                        .font(.largeTitle.weight(.bold))

                    settingsCard(title: t("外观与语言", "Appearance & Language"), icon: "paintbrush.pointed.fill") {
                        Picker(t("语言", "Language"), selection: Binding(
                            get: { preferences.language },
                            set: { preferences.setLanguage($0) }
                        )) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }

                        Picker(t("主题", "Theme"), selection: Binding(
                            get: { preferences.theme },
                            set: { preferences.setTheme($0) }
                        )) {
                            Text(t("跟随系统", "Follow System")).tag(AppTheme.system)
                            Text(t("浅色", "Light")).tag(AppTheme.light)
                            Text(t("深色", "Dark")).tag(AppTheme.dark)
                        }
                    }

                    settingsCard(title: t("终端应用", "Terminal Apps"), icon: "terminal") {
                        Button(t("检测已安装终端应用", "Detect Installed Terminal Apps")) {
                            preferences.refreshInstalledApps()
                        }

                        if let lastScannedAt = preferences.lastScannedAt {
                            Text("\(t("最近检测", "Last scanned")): \(lastScannedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(t("尚未检测，默认直接使用系统应用打开 SSH。", "No scan yet. SSH opens with the system app by default."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if preferences.installedApps.isEmpty {
                            Text(t("暂无缓存结果。点击上方按钮按需检测一次。", "No cached results yet. Click the button above to scan on demand."))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(preferences.installedApps) { app in
                                    HStack {
                                        Image(systemName: "app.fill")
                                            .foregroundStyle(Color.accentColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name)
                                            Text(app.path)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.primary.opacity(0.04))
                                    )
                                }
                            }
                        }
                    }

                    settingsCard(title: t("数据管理", "Data Management"), icon: "externaldrive.fill.badge.person.crop") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Button(t("导出数据", "Export Data")) {
                                    exportConnections()
                                }

                                Button(t("导入数据", "Import Data")) {
                                    importConnections()
                                }

                                Button(t("清空全部数据", "Clear All Data"), role: .destructive) {
                                    showClearConfirmation = true
                                }
                            }

                            Text(t("导出为 JSON，导入会直接替换当前全部连接记录。", "Exports JSON. Import replaces all current connection records."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 640, height: 560)
        .alert(t("操作失败", "Operation Failed"), isPresented: Binding(
            get: { !settingsErrorMessage.isEmpty },
            set: { isPresented in
                if !isPresented {
                    settingsErrorMessage = ""
                }
            }
        )) {
            Button("OK") {
                settingsErrorMessage = ""
            }
        } message: {
            Text(settingsErrorMessage)
        }
        .confirmationDialog(
            t("确认清空全部数据？", "Clear all data?"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("清空全部数据", "Clear All Data"), role: .destructive) {
                store.clearAll()
            }
            Button(t("取消", "Cancel"), role: .cancel) {
            }
        } message: {
            Text(t("此操作不可撤销，所有 SSH 连接和系统历史都会被删除。", "This cannot be undone. All SSH connections and system history will be removed."))
        }
    }

    private func settingsCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private func exportConnections() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "swiftgnuinfo-connections.json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try store.exportData()
            try data.write(to: url, options: .atomic)
        } catch {
            settingsErrorMessage = error.localizedDescription
        }
    }

    private func importConnections() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            try store.importData(from: data)
        } catch {
            settingsErrorMessage = error.localizedDescription
        }
    }
}

private struct ConnectionRowView: View {
    let connection: SSHConnection
    let isSelected: Bool
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
                Image(systemName: "terminal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(connection.displayName.isEmpty ? connection.host : connection.displayName)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
        )
        .shadow(color: .black.opacity(isSelected ? 0.06 : 0.03), radius: isSelected ? 10 : 6, x: 0, y: 4)
        .foregroundStyle(.primary)
    }
}

private struct SidebarSeparatorRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)

            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)
        }
        .padding(.vertical, 10)
    }
}
