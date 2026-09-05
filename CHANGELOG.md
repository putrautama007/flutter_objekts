# Changelog

## Unreleased

## 0.1.2

### Changes

- Merge pull request #3 from putrautama007/codex/sync-readme-release-version

- chore(release): sync README install version

## 0.1.1

### Changes

- Added `runScreenshotBatch` with bounded background PNG encoding and ordered
  screenshot results for faster multi-screen widget tests.
- Added batched golden comparisons while preserving the existing synchronous
  screenshot and golden interfaces.
- Added collision-free device × Flutter variant artifact directories.
- Added a repeatable two-device, four-screen performance benchmark.

- Merge pull request #2 from putrautama007/codex/faster-batched-screenshots

- feat: add faster batched screenshot processing

## 0.1.0

- Initial GitHub-hosted release.
- Added full-surface and focused Finder PNG capture.
- Added opt-in failure screenshots.
- Added device-framed and ordered multi-device widget tests.

### Changes

- Added `matchesGolden` for exact Flutter golden file comparisons.
- Added deterministic golden baseline paths and support for
  `flutter test --update-goldens`.

- Merge pull request #1 from putrautama007/codex/release-pipeline

- Add automatic GitHub release pipeline

- Add golden file testing

- feat: add multi-screen screenshot example

- fix: render real fonts in screenshots

- feat: add Flutter widget screenshot package

- Initial commit
