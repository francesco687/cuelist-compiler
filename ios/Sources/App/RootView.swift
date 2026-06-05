import SwiftUI
import CuelistCompilerKit

struct RootView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(VoiceCaptureController.self) private var voice
    @State private var showSettings = false
    @State private var showDefaults = false
    @State private var showPull = false
    @State private var showNotes = false
    @State private var showRename = false
    @State private var renameText = ""

    private var activeIndex: Int? {
        store.project.songs.firstIndex(where: { $0.id == store.project.activeSongId })
    }

    var body: some View {
        TabView {
            authorTab
                .tabItem { Label("Author", systemImage: "square.and.pencil") }
            SendView()
                .tabItem { Label("Send", systemImage: "paperplane") }
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
                    CueListView()
                    TalkBarView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { songMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNotes = true } label: {
                        Image(systemName: "square.and.pencil").foregroundStyle(Theme.aqua)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showPull = true } label: { Label("Pull from MA\u{2026}", systemImage: "arrow.down.circle") }
                        Divider()
                        Button("Defaults\u{2026}") { showDefaults = true }
                        Button("Settings\u{2026}") { showSettings = true }
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showDefaults) { DefaultsView() }
            .sheet(isPresented: $showPull) { PullSequencesView() }
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
                        Image(systemName: "rectangle.compress.vertical")
                            .font(.system(size: 14)).foregroundStyle(Theme.accentSolid)
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation(.snappy(duration: 0.2)) { store.expandAllCues() } } label: {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.system(size: 14)).foregroundStyle(Theme.accentSolid)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(store.project.songs[i].cues.count) cue\(store.project.songs[i].cues.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
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
