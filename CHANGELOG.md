# Changelog

## 1.3.0 — 2026-11-13

- Added perceptual album-artwork comparison as an additional matching signal.
- Reject candidates whose artwork clearly belongs to another album.
- Cache downloaded artwork during a scan.
- Preserved all existing language and position checks.

## 1.2.1 — 2026-11-13

- Fixed a cross-album false positive that could match `Shandy Gaff` to `Aoi`.
- Required matching track positions to agree on duration before accepting a result.
- Added explicit mappings for `Adapt` / `アダプト(ADAPT)` and
  `Shandy Gaff` / `シャンディガフ`.

## 1.2.0 — 2026-11-13

- Added a precision macOS-style icon featuring a bass clef and correction gear.
- Added second-pass matching by song title when album matching fails.
- Added Simplified/Traditional Chinese comparison.
- Added multilingual title preservation rules.
- Split unmatched songs into actionable and likely-correct categories.
- Renamed the app and installer to `Apple Music 音乐信息订正`.
- Added one-click rollback for each metadata change.

## 1.0.0

- Initial macOS application.
