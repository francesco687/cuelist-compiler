import SwiftUI
import SaettaKit

struct RootView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(VoiceCaptureController.self) private var voice
    @State private var showNotes = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<UUID> = []

    private var activeIndex: Int? {
        store.project.songs.firstIndex(where: { $0.id == store.project.activeSongId })
    }

    var body: some View {
        TabView {
            LiveView()
                .tabItem { Label("Live", systemImage: "play.circle.fill") }
            authorTab
                .tabItem { Label("Author", systemImage: "square.and.pencil") }
            SendView()
                .tabItem { Label("Send", systemImage: "paperplane") }
            SettingsTabView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accentSolid)
    }

    private var authorTab: some View {
        @Bindable var store = store
        return NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 0) {
                    subbar
                    CueListView(selection: $selection)
                    if editMode == .active {
                        deleteBar
                    } else {
                        BottomCluster(onAddCue: { store.addCue() },
                                      onNote: { showNotes = true })
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { songMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode == .active ? "Done" : "Edit") {
                        let turningOff = editMode == .active
                        withAnimation { editMode = turningOff ? .inactive : .active }
                        if turningOff { selection.removeAll() }
                    }
                    .foregroundStyle(Theme.accentSolid)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showNotes) { NotesCaptureView(targetCue: nil) }
            .sheet(isPresented: previewBinding) {
                if let pending = voice.pending {
                    VoicePreviewSheet(
                        pending: pending,
                        onApply: { store.apply(pending.result); voice.cancel() },
                        onDiscard: { voice.cancel() }
                    )
                }
            }
            .alert("Voice", isPresented: errorBinding) {
                Button("OK") { voice.cancel() }
            } message: { Text(errorText) }
            .alert("Rename song", isPresented: $showRename) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let i = activeIndex { store.project.songs[i].name = renameText }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder private var deleteBar: some View {
        Button(role: .destructive) {
            store.removeCues(ids: selection); selection.removeAll()
        } label: {
            Text(selection.isEmpty ? "Select cues to delete"
                                   : "Delete \(selection.count) cue\(selection.count == 1 ? "" : "s")")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(selection.isEmpty ? Theme.surface2 : Theme.danger,
                            in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                .foregroundStyle(selection.isEmpty ? Theme.textDim : .white)
        }
        .buttonStyle(.plain).disabled(selection.isEmpty)
        .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
    }

    // MARK: Song menu (in nav title)

    @ViewBuilder private var songMenu: some View {
        let name = store.activeSong.name.isEmpty ? "(untitled)" : store.activeSong.name
        Menu {
            ForEach(store.project.songs) { song in
                Button {
                    store.setActiveSong(song.id)
                } label: {
                    Label(song.name.isEmpty ? "(untitled)" : song.name,
                          systemImage: song.id == store.project.activeSongId ? "checkmark" : "music.note")
                }
            }
            Divider()
            Button("New Song") { store.addSong() }
            Button("Rename…") {
                renameText = store.activeSong.name; showRename = true
            }
            if store.project.songs.count > 1 {
                Button("Remove \u{201C}\(name)\u{201D}", role: .destructive) {
                    store.removeSong(id: store.project.activeSongId)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Theme.accentSolid)
            }
        }
    }

    // MARK: Slim subbar (seq + cue count)

    @ViewBuilder private var subbar: some View {
        @Bindable var store = store
        if let i = activeIndex {
            HStack(spacing: 12) {
                SeqField(sequence: $store.project.songs[i].sequence)
                if !store.project.songs[i].cues.isEmpty {
                    Button { withAnimation(.snappy(duration: 0.2)) { store.collapseAllCues() } } label: {
                        subbarIcon("rectangle.compress.vertical")
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation(.snappy(duration: 0.2)) { store.expandAllCues() } } label: {
                        subbarIcon("rectangle.expand.vertical")
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation(.snappy(duration: 0.2)) { store.renumberFromOne() } } label: {
                        subbarIcon("list.number")
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(store.project.songs[i].cues.count) cue\(store.project.songs[i].cues.count == 1 ? "" : "s")")
                    .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
    }

    private func subbarIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.accentSolid)
            .frame(width: 40, height: 40)
            .background(Theme.surface3, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var previewBinding: Binding<Bool> {
        Binding(get: { if case .preview = voice.phase { return true } else { return false } },
                set: { if !$0 { voice.cancel() } })
    }
    private var errorBinding: Binding<Bool> {
        Binding(get: { if case .error = voice.phase { return true } else { return false } },
                set: { if !$0 { voice.cancel() } })
    }
    private var errorText: String {
        if case let .error(m) = voice.phase { return m } else { return "" }
    }
}
