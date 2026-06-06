# Changelog

All notable changes to this project are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- Restructured into a monorepo (`web/ ios/ proxy/ shared/ docs/`).
- Split the single-file web app into no-build modules under `web/js/` with a
  `CC.<module>` public surface; extracted CSS to `web/css/styles.css`.

### Added
- `shared/ma3-command-spec.md` — the MA3 command contract both frontends implement.
- `docs/architecture.md`; contribution infra (CONTRIBUTING, PR/issue templates,
  editorconfig, expanded gitignore, changelog).
- `proxy/start.sh` for macOS/Linux.
- **web:** Timecode per cue — author SMPTE positions per cue and push to MA3
  Timecode pool via `Send TC current/all → MA` (Lua Object API, Overwrite-only;
  see `shared/ma3-command-spec.md` §Timecode show). Pre-condition: Track in
  TC pool created on MA3 first.
- iOS app renamed to **Saetta**. Send tab split into Send Cues / Send Notes /
  Send Timecode. New per-cue timecode tick box: ticked cues are written to the
  grandMA3 Timecode pool (Lua Object API, per-cue upsert) — re-sending a cue
  replaces its event instead of duplicating, and events for other cues are left
  untouched. The send Lua self-reports via `Printf` to MA3's System Monitor.
