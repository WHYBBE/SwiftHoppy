import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SSHConnectionStore
    @EnvironmentObject private var preferences: AppPreferencesStore
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
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
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea()

                Group {
                    if store.connections.isEmpty {
                        sidebarEmptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
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
                                    Label(sortModeLabel, systemImage: "arrow.up.arrow.down")
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.primary.opacity(0.06))
                                        )
                                }
                                .menuStyle(.borderlessButton)

                                Toggle(isOn: Binding(
                                    get: { preferences.hidesSensitiveInfo },
                                    set: { preferences.setHidesSensitiveInfo($0) }
                                )) {
                                    Image(systemName: preferences.hidesSensitiveInfo ? "eye.slash" : "eye")
                                        .frame(width: 14)
                                }
                                .toggleStyle(.button)
                                .frame(width: 32, height: 32)
                                .help(t("隐藏左侧栏中的 IP 等关键信息", "Hide IP and other sensitive details in the sidebar"))

                                Spacer(minLength: 4)

                                if preferences.connectionSortMode == .manual {
                                    Button {
                                        _ = store.addSeparator()
                                    } label: {
                                        Image(systemName: "line.3.horizontal")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(t("新增分割线", "Add Divider"))
                                }
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
                                        let isSelected = selectedID == connection.id
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                Text(connection.displayName.isEmpty ? connection.host : connection.displayName)
                                                    .font(.headline)
                                                    .foregroundStyle(isSelected ? .primary : .primary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)

                                                Text(maskedHostText(for: connection))
                                                    .font(.subheadline)
                                                    .foregroundStyle(isSelected ? Color.primary.opacity(0.8) : Color.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }

                                            if let latest = connection.latestSystemInfo,
                                               !latest.kernelVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                Text(latest.kernelVersion)
                                                    .font(.caption)
                                                    .foregroundStyle(isSelected ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.78))
                                                    .lineLimit(1)
                                            }

                                            if let status = updateStatus(for: connection) {
                                                HStack(spacing: 6) {
                                                    Circle()
                                                        .fill(status.color)
                                                        .frame(width: 7, height: 7)

                                                    Text(status.label)
                                                        .font(.caption2)
                                                        .foregroundStyle(isSelected ? Color.primary.opacity(0.82) : status.color)
                                                        .lineLimit(1)
                                                }
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule(style: .continuous)
                                                        .fill(isSelected ? Color.primary.opacity(0.10) : status.color.opacity(0.12))
                                                )
                                                .fixedSize(horizontal: true, vertical: false)
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
                            selectedID = store.firstSelectableID
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
            reconcileSelection()
        }
        .onChange(of: store.connections) { _ in
            reconcileSelection()
        }
        .alert(
            t("数据错误", "Data Error"),
            isPresented: Binding(
                get: {
                    store.persistenceIssue != nil || preferences.persistenceIssue != nil
                },
                set: { isPresented in
                    if !isPresented {
                        store.dismissPersistenceError()
                        preferences.dismissPersistenceError()
                    }
                }
            )
        ) {
            Button(t("好", "OK")) {
                store.dismissPersistenceError()
                preferences.dismissPersistenceError()
            }
        } message: {
            Text(
                store.persistenceIssue?.message(language: preferences.language)
                    ?? preferences.persistenceIssue?.message(language: preferences.language)
                    ?? ""
            )
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
        return store.connections.first(where: { $0.id == selectedID && !$0.isSeparator })
    }

    private func reconcileSelection() {
        if let selectedID,
           store.connections.contains(where: { $0.id == selectedID && !$0.isSeparator }) {
            return
        }
        selectedID = store.firstSelectableID
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

    private func maskedHostText(for connection: SSHConnection) -> String {
        if connection.isLocal {
            return t("本机", "Local")
        }

        let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.hidesSensitiveInfo else {
            return host
        }
        guard !host.isEmpty else {
            return t("未填写主机", "No host")
        }

        return partiallyMasked(host)
    }

    private func partiallyMasked(_ value: String) -> String {
        guard value.count > 4 else {
            return String(repeating: "•", count: value.count)
        }

        let visiblePrefixCount = min(3, max(1, value.count / 4))
        let visibleSuffixCount = min(3, max(1, value.count / 4))
        let maskCount = max(2, value.count - visiblePrefixCount - visibleSuffixCount)
        let prefix = String(value.prefix(visiblePrefixCount))
        let suffix = String(value.suffix(visibleSuffixCount))
        return prefix + String(repeating: "•", count: maskCount) + suffix
    }

    private func deleteConnections(at offsets: IndexSet) {
        let ids = offsets.compactMap { index in
            sortedConnections.indices.contains(index) ? sortedConnections[index].id : nil
        }
        store.connections.removeAll { ids.contains($0.id) }
        if let selectedID, ids.contains(selectedID) {
            self.selectedID = store.firstSelectableID
        }
    }

    private func deleteConnection(id: SSHConnection.ID) {
        store.delete(id: id)
        if selectedID == id {
            selectedID = store.firstSelectableID
        }
    }

    private func updateStatus(for connection: SSHConnection) -> (label: String, color: Color)? {
        guard let latest = connection.latestSystemInfo else {
            return nil
        }
        // Prefer package-update timestamp; fall back to snapshot time (covers manual entries).
        let updateDate = latest.updateRecordedAt ?? latest.recordedAt

        let calendar = Calendar.current
        let startOfUpdateDay = calendar.startOfDay(for: updateDate)
        let startOfToday = calendar.startOfDay(for: .now)
        let days = max(0, calendar.dateComponents([.day], from: startOfUpdateDay, to: startOfToday).day ?? 0)
        let label: String
        if days <= 0 {
            label = t("今天", "Today")
        } else if days < 30 {
            label = "\(days)\(t("天", "d"))"
        } else {
            label = updateDate.formatted(date: .abbreviated, time: .omitted)
        }

        switch days {
        case ..<7:
            return (label, .green)
        case 7..<14:
            return (label, .orange)
        case 14..<30:
            return (label, Color(red: 0.85, green: 0.4, blue: 0.15))
        default:
            return (label, .red)
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
        if connection.isLocal {
            openLocalTerminal(with: connection.preferredAppPath)
            return
        }

        if let validation = connection.validationMessage(language: preferences.language) {
            errorMessage = validation
            return
        }

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
        let failurePrefix = t("打开 SSH 连接失败", "Failed to open SSH connection")
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: appPath), configuration: configuration) { _, error in
            guard let error else { return }
            Task { @MainActor in
                errorMessage = "\(failurePrefix)：\(error.localizedDescription)"
            }
        }
    }

    private func openLocalTerminal(with preferredAppPath: String) {
        let trimmedPath = preferredAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetURL = trimmedPath.isEmpty
            ? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            : URL(fileURLWithPath: trimmedPath)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let failurePrefix = t("打开终端失败", "Failed to open terminal")
        NSWorkspace.shared.openApplication(at: targetURL, configuration: configuration) { _, error in
            guard let error else { return }
            Task { @MainActor in
                errorMessage = "\(failurePrefix)：\(error.localizedDescription)"
            }
        }
    }
}

struct ConnectionDetailView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    let connection: SSHConnection
    @State private var draft: SSHConnection
    @State private var isFetchingSystemInfo = false
    @State private var isFetchingHardwareInfo = false
    @State private var systemInfoFetchTask: Task<Void, Never>?
    @State private var hardwareInfoFetchTask: Task<Void, Never>?
    @State private var fetchErrorMessage = ""
    @State private var showConnectionEditor = false
    @State private var creatingNote = false
    @State private var showNoteSortEditor = false
    @State private var editingNote: NoteEntry?
    @State private var editingSnapshot: SystemInfoSnapshot?
    @State private var creatingManualSnapshot = false
    let installedApps: [InstalledTerminalApp]
    let onSave: (SSHConnection) -> Void
    let onDelete: () -> Void
    let onOpen: (SSHConnection) -> Void
    let errorMessage: String
    let onDismissError: () -> Void
    private let cardShadowOutset: CGFloat = 12

    init(
        connection: SSHConnection,
        installedApps: [InstalledTerminalApp],
        onSave: @escaping (SSHConnection) -> Void,
        onDelete: @escaping () -> Void,
        onOpen: @escaping (SSHConnection) -> Void,
        errorMessage: String,
        onDismissError: @escaping () -> Void
    ) {
        self.connection = connection
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
                            if let hardwareInfo = draft.hardwareInfo, hardwareInfo.hasVisibleContent {
                                hardwareInfoCard(hardwareInfo)
                            }

                            if draft.notesEntries.isEmpty {
                                detailCard(title: t("备注", "Notes"), icon: "note.text") {
                                    Text(t("暂无备注。", "No notes yet."))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                ForEach(sortedNotes) { note in
                                    noteCard(note)
                                }
                            }
                        }
                        .padding(cardShadowOutset)
                    }
                    .padding(-cardShadowOutset)
                    .frame(minWidth: 320, idealWidth: 420, maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 16) {
                        systemHistoryCard
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
        .onChange(of: connection) { newValue in
            // Re-sync when the store version diverges (import/clear/external replace).
            var normalized = draft
            normalized.updatedAt = newValue.updatedAt
            if normalized != newValue {
                draft = newValue
            }
        }
        .onDisappear {
            cancelSystemInfoFetch()
            cancelHardwareFetch()
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
            Button(t("好", "OK")) {
                onDismissError()
                fetchErrorMessage = ""
            }
        } message: {
            Text(fetchErrorMessage.isEmpty ? errorMessage : fetchErrorMessage)
        }
        .sheet(isPresented: $showConnectionEditor) {
            ConnectionInfoEditorView(connection: $draft, installedApps: installedApps)
        }
        .sheet(isPresented: $creatingNote) {
            NoteEditorView(note: NoteEntry(manualOrder: (draft.notesEntries.map(\ .manualOrder).max() ?? -1) + 1), title: t("新建备注", "New Note")) { newNote in
                draft.notesEntries.insert(newNote, at: 0)
            }
        }
        .sheet(isPresented: $showNoteSortEditor) {
            NoteSortEditorView(connection: $draft)
        }
        .sheet(item: $editingNote) { note in
            NoteEditorView(note: note, title: t("编辑备注", "Edit Note")) { updatedNote in
                if let index = draft.notesEntries.firstIndex(where: { $0.id == updatedNote.id }) {
                    draft.notesEntries[index] = updatedNote
                }
            }
        }
        .sheet(item: $editingSnapshot) { snapshot in
            SystemHistoryEditorView(snapshot: snapshot, title: t("编辑系统历史", "Edit System History")) { updatedSnapshot in
                if let index = draft.systemInfoHistory.firstIndex(where: { $0.id == updatedSnapshot.id }) {
                    draft.systemInfoHistory[index] = updatedSnapshot
                }
            }
        }
        .sheet(isPresented: $creatingManualSnapshot) {
            SystemHistoryEditorView(
                snapshot: SystemInfoSnapshot(updateRecordedAt: .now, isManualEntry: true),
                title: t("新建手填历史", "New Manual History")
            ) { newSnapshot in
                draft.systemInfoHistory.insert(newSnapshot, at: 0)
            }
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
                        Label(draft.isLocal ? t("本机", "Local") : (draft.host.isEmpty ? t("未填写主机", "No host") : draft.host), systemImage: draft.isLocal ? "desktopcomputer" : "server.rack")
                        Label("\(t("端口", "Port")) \(draft.port)", systemImage: "shippingbox")
                        if let latest = draft.latestSystemInfo {
                            Label(latest.recordedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            if !latest.uptimeInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Label(latest.uptimeInfo, systemImage: "timer")
                            }
                        }
                    }

                    Label(heroConnectionDetailText, systemImage: draft.isLocal ? "desktopcomputer" : "link")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minHeight: 48, alignment: .topLeading)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(t("编辑信息", "Edit Info")) {
                    showConnectionEditor = true
                }

                Button(t("添加备注", "Add Note")) {
                    creatingNote = true
                }

                Button(draft.isLocal ? t("打开终端", "Open Terminal") : t("打开 SSH", "Open SSH")) {
                    onOpen(draft)
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    if isFetchingHardwareInfo {
                        Button(t("取消获取硬件", "Cancel Hardware Read"), role: .destructive) {
                            cancelHardwareFetch()
                        }
                    } else {
                        Button(t("获取硬件信息", "Read Hardware Info")) {
                            refreshHardwareInfo()
                        }
                    }

                    Button(t("排序备注", "Sort Notes")) {
                        showNoteSortEditor = true
                    }

                    Button(t("删除", "Delete"), role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Label(t("更多", "More"), systemImage: "ellipsis.circle")
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

    private var heroConnectionDetailText: String {
        if draft.isLocal {
            return t("直接打开本机终端", "Open local terminal directly")
        }

        return draft.sshURL?.absoluteString ?? t("SSH 地址不可用", "SSH URL unavailable")
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
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private func noteCard(_ note: NoteEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label(t("备注", "Note"), systemImage: "note.text")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Menu {
                    Button(t("编辑", "Edit")) {
                        editingNote = note
                    }

                    Button(t("删除", "Delete"), role: .destructive) {
                        draft.notesEntries.removeAll { $0.id == note.id }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            Text(note.content)
                .font(.body)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private func hardwareInfoCard(_ info: HardwareInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label(t("硬件信息", "Hardware Info"), systemImage: "cpu")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Menu {
                    if isFetchingHardwareInfo {
                        Button(t("取消", "Cancel"), role: .destructive) {
                            cancelHardwareFetch()
                        }
                    } else {
                        Button(t("更新", "Update")) {
                            refreshHardwareInfo()
                        }
                    }

                    Button(t("删除显示", "Remove Display"), role: .destructive) {
                        draft.hardwareInfo = nil
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            if !info.cpuModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CPU")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(info.cpuModel)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 10) {
                if !info.cpuCores.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hardwareMetricCard(title: t("核心", "Cores"), value: info.cpuCores, icon: "cpu")
                }
                if !info.memoryTotal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hardwareMetricCard(title: t("内存", "Memory"), value: info.memoryTotal, icon: "memorychip")
                }
                if !info.architecture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hardwareMetricCard(title: t("架构", "Arch"), value: info.architecture, icon: "rectangle.3.group")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if !info.osName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hardwareDetailLine(title: t("系统", "System"), value: info.osName)
                }

                hardwareDetailLine(title: t("获取时间", "Read At"), value: info.recordedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18))
        )
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 5)
    }

    private func hardwareMetricCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private func hardwareDetailLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var systemHistoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label(t("系统历史", "System History"), systemImage: "clock.arrow.circlepath")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Menu {
                    if isFetchingSystemInfo {
                        Button(t("取消读取", "Cancel Read"), role: .destructive) {
                            cancelSystemInfoFetch()
                        }
                    } else {
                        Button(draft.isLocal ? t("读取本机信息", "Read Local Info") : t("通过 SSH 读取", "Read via SSH")) {
                            refreshRemoteSystemInfo()
                        }
                    }

                    Button(t("新建手填", "New Manual Entry")) {
                        creatingManualSnapshot = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

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
                        ForEach(draft.systemInfoHistory.sorted { $0.recordedAt > $1.recordedAt }) { snapshot in
                            snapshotCard(snapshot: snapshot)
                                .contextMenu {
                                    Button(t("编辑", "Edit")) {
                                        editingSnapshot = snapshot
                                    }
                                    Button(t("删除", "Delete"), role: .destructive) {
                                        deleteSnapshot(id: snapshot.id)
                                    }
                                }
                        }
                    }
                    .padding(cardShadowOutset)
                }
                .padding(-cardShadowOutset)
            }
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
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private func detailSummaryRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func modernField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .textFieldStyle(.plain)
                .font(.subheadline)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        }
    }

    private func snapshotCard(snapshot: SystemInfoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()

                if snapshot.isManualEntry {
                    Text(t("手填", "Manual"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.blue)
                }

                if snapshot.isEdited {
                    Text(t("已编辑", "Edited"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.purple)
                }
            }

            detailSummaryRow(title: t("内核版本", "Kernel Version"), value: snapshot.kernelVersion.isEmpty ? "-" : snapshot.kernelVersion)
            detailSummaryRow(
                title: t("最后更新信息", "Last Update Info"),
                value: snapshot.updateInfo.isEmpty
                    ? t("未检测到更新信息", "No update info detected")
                    : snapshot.updateInfo
            )

            if !snapshot.uptimeInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                detailSummaryRow(title: t("运行时间", "Uptime"), value: snapshot.uptimeInfo)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private func refreshRemoteSystemInfo() {
        systemInfoFetchTask?.cancel()
        let snapshot = draft
        isFetchingSystemInfo = true
        fetchErrorMessage = ""

        systemInfoFetchTask = Task {
            do {
                let info = try await RemoteSystemInfoService.fetch(for: snapshot)
                guard !Task.isCancelled else { return }
                draft.systemInfoHistory.insert(
                    SystemInfoSnapshot(
                        kernelVersion: info.kernelVersion,
                        updateInfo: info.updateInfo,
                        uptimeInfo: info.uptimeInfo,
                        updateRecordedAt: info.updateRecordedAt,
                        isManualEntry: false,
                        isEdited: false,
                        recordedAt: info.recordedAt
                    ),
                    at: 0
                )
                isFetchingSystemInfo = false
                systemInfoFetchTask = nil
            } catch {
                if error is CancellationError {
                    isFetchingSystemInfo = false
                    systemInfoFetchTask = nil
                    return
                }
                fetchErrorMessage = localizedFetchError(error)
                isFetchingSystemInfo = false
                systemInfoFetchTask = nil
            }
        }
    }

    private func refreshHardwareInfo() {
        hardwareInfoFetchTask?.cancel()
        let snapshot = draft
        isFetchingHardwareInfo = true
        fetchErrorMessage = ""

        hardwareInfoFetchTask = Task {
            do {
                let info = try await RemoteSystemInfoService.fetchHardware(for: snapshot)
                guard !Task.isCancelled else { return }
                draft.hardwareInfo = info
                isFetchingHardwareInfo = false
                hardwareInfoFetchTask = nil
            } catch {
                if error is CancellationError {
                    isFetchingHardwareInfo = false
                    hardwareInfoFetchTask = nil
                    return
                }
                fetchErrorMessage = localizedFetchError(error)
                isFetchingHardwareInfo = false
                hardwareInfoFetchTask = nil
            }
        }
    }

    private func cancelSystemInfoFetch() {
        systemInfoFetchTask?.cancel()
        systemInfoFetchTask = nil
        isFetchingSystemInfo = false
    }

    private func cancelHardwareFetch() {
        hardwareInfoFetchTask?.cancel()
        hardwareInfoFetchTask = nil
        isFetchingHardwareInfo = false
    }

    private func localizedFetchError(_ error: Error) -> String {
        if error is CancellationError {
            return RemoteSystemInfoError.cancelled.message(language: preferences.language)
        }
        if let remoteError = error as? RemoteSystemInfoError {
            return remoteError.message(language: preferences.language)
        }
        return error.localizedDescription
    }

    private func deleteSnapshot(id: SystemInfoSnapshot.ID) {
        draft.systemInfoHistory.removeAll { $0.id == id }
    }

    private var sortedNotes: [NoteEntry] {
        switch draft.noteSortMode {
        case .manual:
            return draft.notesEntries.sorted {
                if $0.manualOrder == $1.manualOrder {
                    return $0.createdAt > $1.createdAt
                }
                return $0.manualOrder < $1.manualOrder
            }
        case .time:
            return draft.notesEntries.sorted { $0.createdAt > $1.createdAt }
        }
    }

}

struct ConnectionInfoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: AppPreferencesStore
    @Binding var connection: SSHConnection
    @State private var draft: SSHConnection
    @State private var validationMessage = ""
    let installedApps: [InstalledTerminalApp]

    init(
        connection: Binding<SSHConnection>,
        installedApps: [InstalledTerminalApp]
    ) {
        self._connection = connection
        self._draft = State(initialValue: connection.wrappedValue)
        self.installedApps = installedApps
    }

    private func t(_ chinese: String, _ english: String) -> String {
        preferences.text(chinese, english)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(t("连接信息", "Connection")) {
                    TextField(t("名称", "Name"), text: $draft.name)
                    Toggle(t("标记为本地", "Mark as Local"), isOn: $draft.isLocal)

                    if !draft.isLocal {
                        TextField(t("主机", "Host"), text: $draft.host)
                        TextField(t("用户名", "Username"), text: $draft.username)
                        TextField(t("端口", "Port"), value: $draft.port, format: .number)
                    }
                }

                Section(t("打开方式", "Open With")) {
                    Picker(t("已安装应用", "Installed Apps"), selection: $draft.preferredAppPath) {
                        Text(t("系统默认", "System Default")).tag("")
                        ForEach(installedApps) { app in
                            Text(app.name).tag(app.path)
                        }
                    }

                    HStack {
                        Button(t("选择应用", "Choose Application")) {
                            chooseApplicationForDraft()
                        }
                        if !draft.preferredAppPath.isEmpty {
                            Button(t("清除", "Clear")) {
                                draft.preferredAppPath = ""
                            }
                        }
                    }
                }

                if !validationMessage.isEmpty {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 520, height: 440)
            .navigationTitle(t("编辑信息", "Edit Info"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("取消", "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("完成", "Done")) {
                        if let message = draft.validationMessage(language: preferences.language) {
                            validationMessage = message
                            return
                        }
                        connection = draft
                        dismiss()
                    }
                }
            }
        }
    }

    private func chooseApplicationForDraft() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK {
            draft.preferredAppPath = panel.url?.path ?? ""
        }
    }
}

struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: AppPreferencesStore
    @State private var note: NoteEntry
    @State private var validationMessage = ""
    let title: String
    let onSave: (NoteEntry) -> Void

    init(note: NoteEntry, title: String, onSave: @escaping (NoteEntry) -> Void) {
        self._note = State(initialValue: note)
        self.title = title
        self.onSave = onSave
    }

    private func t(_ chinese: String, _ english: String) -> String {
        preferences.text(chinese, english)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $note.content)
                    .frame(minHeight: 220)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )

                if !validationMessage.isEmpty {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding()
            .frame(width: 560, height: 360)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("取消", "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("保存", "Save")) {
                        if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            validationMessage = t("备注内容不能为空。", "Note content cannot be empty.")
                            return
                        }
                        onSave(note)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct NoteSortEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: AppPreferencesStore
    @Binding var connection: SSHConnection
    @State private var draft: SSHConnection

    init(connection: Binding<SSHConnection>) {
        self._connection = connection
        self._draft = State(initialValue: connection.wrappedValue)
    }

    private func t(_ chinese: String, _ english: String) -> String {
        preferences.text(chinese, english)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker(t("排序模式", "Sort Mode"), selection: $draft.noteSortMode) {
                    Text(t("手动", "Manual")).tag(NoteSortMode.manual)
                    Text(t("时间", "Time")).tag(NoteSortMode.time)
                }
                .pickerStyle(.segmented)

                List {
                    ForEach(sortedNotes) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.content)
                                .lineLimit(2)
                            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onMove(perform: draft.noteSortMode == .manual ? moveNotes : nil)
                }
            }
            .padding()
            .frame(width: 560, height: 480)
            .navigationTitle(t("排序备注", "Sort Notes"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("取消", "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("完成", "Done")) {
                        connection = draft
                        dismiss()
                    }
                }
            }
        }
    }

    private var sortedNotes: [NoteEntry] {
        switch draft.noteSortMode {
        case .manual:
            return draft.notesEntries.sorted {
                if $0.manualOrder == $1.manualOrder {
                    return $0.createdAt > $1.createdAt
                }
                return $0.manualOrder < $1.manualOrder
            }
        case .time:
            return draft.notesEntries.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func moveNotes(from source: IndexSet, to destination: Int) {
        guard draft.noteSortMode == .manual else { return }
        var notes = sortedNotes
        notes.move(fromOffsets: source, toOffset: destination)
        for index in notes.indices {
            notes[index].manualOrder = index
        }
        draft.notesEntries = notes
    }
}

struct SystemHistoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: AppPreferencesStore
    @State private var snapshot: SystemInfoSnapshot
    @State private var validationMessage = ""
    let title: String
    let onSave: (SystemInfoSnapshot) -> Void

    init(snapshot: SystemInfoSnapshot, title: String, onSave: @escaping (SystemInfoSnapshot) -> Void) {
        self._snapshot = State(initialValue: snapshot)
        self.title = title
        self.onSave = onSave
    }

    private func t(_ chinese: String, _ english: String) -> String {
        preferences.text(chinese, english)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(t("内核版本", "Kernel Version"), text: $snapshot.kernelVersion)
                TextField(t("最后更新信息", "Last Update Info"), text: $snapshot.updateInfo)
                TextField(t("运行时间", "Uptime"), text: $snapshot.uptimeInfo)
                DatePicker(
                    t("更新日期", "Update Date"),
                    selection: Binding(
                        get: { snapshot.updateRecordedAt ?? snapshot.recordedAt },
                        set: { snapshot.updateRecordedAt = $0 }
                    ),
                    displayedComponents: [.date]
                )

                if !validationMessage.isEmpty {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)
            .frame(width: 520, height: 380)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("取消", "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("保存", "Save")) {
                        let hasContent = [snapshot.kernelVersion, snapshot.updateInfo, snapshot.uptimeInfo]
                            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        guard hasContent else {
                            validationMessage = t("请至少填写一项内容。", "Fill in at least one field.")
                            return
                        }
                        if snapshot.updateRecordedAt == nil {
                            snapshot.updateRecordedAt = snapshot.recordedAt
                        }
                        snapshot.isEdited = true
                        onSave(snapshot)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: SSHConnectionStore
    @EnvironmentObject private var preferences: AppPreferencesStore
    @State private var settingsErrorMessage = ""
    @State private var settingsInfoMessage = ""
    @State private var showClearConfirmation = false
    @State private var importPreview: ImportPreview?

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
                                    pickImportFile()
                                }

                                Button(t("清空全部数据", "Clear All Data"), role: .destructive) {
                                    showClearConfirmation = true
                                }
                            }

                            Text(t(
                                "导出为 JSON。导入前会预览并可选择合并或替换；导入与清空前会自动备份到 Application Support/SwiftHoppy/Backups。",
                                "Exports JSON. Import shows a preview with merge or replace; import and clear auto-backup to Application Support/SwiftHoppy/Backups."
                            ))
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
            get: {
                !settingsErrorMessage.isEmpty
                    || store.persistenceIssue != nil
                    || preferences.persistenceIssue != nil
            },
            set: { isPresented in
                if !isPresented {
                    settingsErrorMessage = ""
                    store.dismissPersistenceError()
                    preferences.dismissPersistenceError()
                }
            }
        )) {
            Button(t("好", "OK")) {
                settingsErrorMessage = ""
                store.dismissPersistenceError()
                preferences.dismissPersistenceError()
            }
        } message: {
            Text(
                settingsErrorMessage.isEmpty
                    ? (store.persistenceIssue?.message(language: preferences.language)
                        ?? preferences.persistenceIssue?.message(language: preferences.language)
                        ?? "")
                    : settingsErrorMessage
            )
        }
        .alert(t("完成", "Done"), isPresented: Binding(
            get: { !settingsInfoMessage.isEmpty },
            set: { isPresented in
                if !isPresented {
                    settingsInfoMessage = ""
                }
            }
        )) {
            Button(t("好", "OK")) {
                settingsInfoMessage = ""
            }
        } message: {
            Text(settingsInfoMessage)
        }
        .sheet(item: $importPreview) { preview in
            ImportPreviewSheet(
                preview: preview,
                existingConnections: store.connections,
                onCancel: { importPreview = nil },
                onConfirm: { mode in
                    confirmImport(preview, mode: mode)
                }
            )
        }
        .confirmationDialog(
            t("确认清空全部数据？", "Clear all data?"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("清空全部数据", "Clear All Data"), role: .destructive) {
                clearAllWithBackup()
            }
            Button(t("取消", "Cancel"), role: .cancel) {
            }
        } message: {
            Text(t(
                "当前数据会先自动备份，然后删除全部 SSH 连接与系统历史。",
                "Current data is backed up first, then all SSH connections and system history are removed."
            ))
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
        panel.nameFieldStringValue = "swifthoppy-connections.json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try store.exportData()
            try data.write(to: url, options: .atomic)
        } catch {
            settingsErrorMessage = localizedSettingsError(error)
        }
    }

    private func pickImportFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            importPreview = try store.previewImport(from: data, sourceFileName: url.lastPathComponent)
        } catch {
            settingsErrorMessage = localizedSettingsError(error)
        }
    }

    private func confirmImport(_ preview: ImportPreview, mode: ImportMode) {
        do {
            let backupURL = try store.applyImport(preview, mode: mode)
            importPreview = nil
            var message = mode == .merge
                ? t("已合并导入连接。", "Connections merged successfully.")
                : t("已替换全部连接。", "All connections replaced successfully.")
            if let backupURL {
                message += "\n" + t("备份：", "Backup: ") + backupURL.lastPathComponent
            }
            settingsInfoMessage = message
        } catch {
            settingsErrorMessage = localizedSettingsError(error)
        }
    }

    private func clearAllWithBackup() {
        do {
            let backupURL = try store.clearAllPreservingBackup()
            var message = t("已清空全部连接数据。", "All connection data cleared.")
            if let backupURL {
                message += "\n" + t("备份：", "Backup: ") + backupURL.lastPathComponent
            }
            settingsInfoMessage = message
        } catch {
            settingsErrorMessage = localizedSettingsError(error)
        }
    }

    private func localizedSettingsError(_ error: Error) -> String {
        if let storeError = error as? SSHConnectionStoreError {
            return storeError.message(language: preferences.language)
        }
        return error.localizedDescription
    }
}

struct ImportPreviewSheet: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    let preview: ImportPreview
    let existingConnections: [SSHConnection]
    let onCancel: () -> Void
    let onConfirm: (ImportMode) -> Void
    @State private var mode: ImportMode = .merge

    private func t(_ chinese: String, _ english: String) -> String {
        preferences.text(chinese, english)
    }

    private var newCount: Int {
        preview.newCount(against: existingConnections)
    }

    private var duplicateCount: Int {
        preview.duplicateCount(against: existingConnections)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(preview.sourceFileName)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(t("当前记录", "Current records")): \(existingConnections.count)")
                    Text("\(t("文件条目", "Items in file")): \(preview.importedCount) (\(preview.connectionCount) \(t("连接", "connections")), \(preview.separatorCount) \(t("分割线", "dividers")))")
                    Text("\(t("可新增", "Would add")): \(newCount) · \(t("重复 ID", "Duplicate IDs")): \(duplicateCount)")
                }
                .font(.callout)

                Picker(t("导入方式", "Import mode"), selection: $mode) {
                    Text(t("合并（仅添加新 ID）", "Merge (add new IDs only)")).tag(ImportMode.merge)
                    Text(t("替换全部", "Replace all")).tag(ImportMode.replace)
                }
                .pickerStyle(.radioGroup)

                if mode == .replace {
                    Text(t(
                        "替换会覆盖当前全部连接；操作前会自动备份。",
                        "Replace overwrites all current connections; a backup is created first."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.orange)
                } else {
                    Text(t(
                        "合并会保留现有连接，只追加文件中尚未存在的 ID；操作前会自动备份。",
                        "Merge keeps existing connections and appends only IDs not already present; a backup is created first."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                List {
                    ForEach(preview.items.prefix(30)) { item in
                        HStack {
                            Image(systemName: item.isSeparator ? "line.3.horizontal" : "server.rack")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.isSeparator ? t("分割线", "Divider") : (item.displayName.isEmpty ? item.host : item.displayName))
                                    .lineLimit(1)
                                if !item.isSeparator {
                                    Text(item.isLocal ? t("本机", "Local") : "\(item.host):\(item.port)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                    }
                    if preview.items.count > 30 {
                        Text(t("仅显示前 30 条…", "Showing first 30 items…"))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 220)
            }
            .padding()
            .frame(width: 520, height: 520)
            .navigationTitle(t("导入预览", "Import Preview"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("取消", "Cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .replace ? t("替换", "Replace") : t("合并", "Merge")) {
                        onConfirm(mode)
                    }
                    .disabled(mode == .merge && newCount == 0 && preview.importedCount > 0 && duplicateCount == preview.importedCount)
                }
            }
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
