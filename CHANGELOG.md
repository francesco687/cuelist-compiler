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
