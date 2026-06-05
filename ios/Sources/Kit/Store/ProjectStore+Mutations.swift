import Foundation

public extension ProjectStore {

    /// The active song, or the first one (never nil — Project always has ≥1 song).
    var activeSong: Song {
        project.activeSong ?? project.songs[0]
    }

    private func activeSongIndex() -> Int {
        project.songs.firstIndex(where: { $0.id == project.activeSongId })
            ?? 0
    }

    // MARK: Songs

    func addSong() {
        let s = Song(id: IDGen.next(), sequence: 1, cues: [])
        project.songs.append(s)
        project.activeSongId = s.id
    }

    func setActiveSong(_ id: String) {
        project.activeSongId = id
    }

    func removeSong(id: String) {
        guard let idx = project.songs.firstIndex(where: { $0.id == id }) else { return }
        project.songs.remove(at: idx)
        if project.songs.isEmpty {
            let ns = Song(id: IDGen.next(), sequence: 1, cues: [])
            project.songs = [ns]
            project.activeSongId = ns.id
        } else if project.activeSongId == id {
            project.activeSongId = project.songs[max(0, idx - 1)].id
        }
    }

    // MARK: Cues (operate on the active song)

    func addCue() {
        let i = activeSongIndex()
        let nextN = (project.songs[i].cues.map(\.n).max() ?? 0) + 1
        project.songs[i].cues.append(Cue(n: nextN))
    }

    func removeCue(id: UUID) {
        let i = activeSongIndex()
        project.songs[i].cues.removeAll { $0.id == id }
    }

    func sortActiveCues() {
        let i = activeSongIndex()
        project.songs[i].cues.sort { $0.n < $1.n }
    }

    /// Edit one cue of the active song in place.
    func updateActiveCue(id: UUID, _ edit: (inout Cue) -> Void) {
        let i = activeSongIndex()
        guard let c = project.songs[i].cues.firstIndex(where: { $0.id == id }) else { return }
        edit(&project.songs[i].cues[c])
    }

    // MARK: Action blocks

    func addActionBlock(cueId: UUID) {
        updateActiveCue(id: cueId) { $0.actions.append(Action()) }
    }

    func removeActionBlock(cueId: UUID, at index: Int) {
        updateActiveCue(id: cueId) { cue in
            guard cue.actions.indices.contains(index) else { return }
            cue.actions.remove(at: index)
            if cue.actions.isEmpty { cue.actions.append(Action()) }   // never zero
        }
    }

    /// Replace the target cue's action blocks with a deep copy of the source cue's.
    func copyActions(fromCueId src: UUID, toCueId dst: UUID) {
        let i = activeSongIndex()
        guard let s = project.songs[i].cues.firstIndex(where: { $0.id == src }) else { return }
        let cloned = project.songs[i].cues[s].actions
        updateActiveCue(id: dst) { $0.actions = cloned }
    }

    /// Append notes onto cues of the active song by cue number `n`. Newline-joins
    /// onto any existing note; trims and skips empty text or unknown cue numbers.
    func applyNotes(_ edits: [NoteEdit]) {
        let i = activeSongIndex()
        for e in edits {
            let t = e.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty,
                  let c = project.songs[i].cues.firstIndex(where: { $0.n == e.cue }) else { continue }
            let existing = project.songs[i].cues[c].notes
            project.songs[i].cues[c].notes = existing.isEmpty ? t : existing + "\n" + t
        }
    }
    /// Convenience for the per-cue note button.
    func appendNote(cueN: Double, text: String) {
        applyNotes([NoteEdit(cue: cueN, text: text)])
    }

    /// Overwrite (or clear) the note of the active song's cue number `n`.
    /// Empty/whitespace text clears the note. Unknown cue numbers are ignored.
    func setNote(cueN n: Double, text: String) {
        let i = activeSongIndex()
        guard let c = project.songs[i].cues.firstIndex(where: { $0.n == n }) else { return }
        project.songs[i].cues[c].notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Commit a precomputed voice-edit result (project + defaults) in one shot.
    /// Triggers the store's normal debounced save via the `project`/`defaults` didSet.
    func apply(_ result: ApplyResult) {
        project = result.project
        defaults = result.defaults
    }
}
