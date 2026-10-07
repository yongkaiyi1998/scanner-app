# TASKS.md

## Rules
Tasks are executed in order unless the Coordinator changes the plan. A task is complete only when its acceptance criteria and required checks pass.

Model guidance is optimized for ChatGPT Plus Codex usage:
- `GPT-5.6 Terra`: routine, bounded implementation when available.
- `GPT-6.1 Sol Low` (the UI may label this as Light): default for normal feature work.
- `GPT-6.1 Sol Medium`: native integration, image processing, device/runtime diagnosis.
- Escalate to High only after a scoped problem actually needs deeper reasoning. Use Astra only for a genuinely stuck, high-complexity issue.

Model labels can change; use the nearest equivalent rather than blocking the project.

---

## 01 — FOUNDATION-001
**Model:** GPT-5.6 Terra  
**Goal:** Create the Flutter project foundation.

**Deliver**
- Stable Flutter project builds.
- Feature-first folders matching `ARCHITECTURE.md`.
- Base theme, app shell, Home placeholder, editor/history route placeholders.
- Project lints and test baseline.
- Only dependencies needed immediately.

**Accept**
- `flutter analyze` passes.
- Baseline tests pass.
- Android debug build succeeds.
- No scanner/editor implementation yet.

---

## 02 — CAPTURE-001
**Model:** GPT-6.1 Sol Low  
**Goal:** Implement Home capture/import entry points.

**Deliver**
- Scan Document action.
- Gallery/system Photo Picker import path.
- Safe URI/file validation and cancellation handling.
- Imported image copied into controlled working storage when persistence requires it.

**Accept**
- Valid gallery image reaches a preview/result state.
- Cancel/invalid/unreadable input does not crash.
- No broad Android storage permission unless proven necessary.

---

## 03 — SCAN-001
**Model:** GPT-6.1 Sol Medium  
**Goal:** Integrate Android ML Kit Document Scanner.

**Deliver**
- Scanner service boundary.
- Maintained Flutter integration or thin Kotlin bridge.
- Scanner launch/result handling.
- JPEG page results returned to Flutter.
- Unsupported/unavailable/cancelled/error states mapped to app errors.

**Accept**
- Real Android device completes a one-page scan.
- Automatic document correction comes from the scanner flow.
- App survives cancellation and scanner failure.
- No custom CV edge detector is added.

---

## 04 — SCAN-002
**Model:** GPT-6.1 Sol Low  
**Goal:** Normalize scan/import results into app-owned document pages.

**Deliver**
- Document/Page models needed by subsequent tasks.
- Copy/normalize persistent page files.
- Orientation/result normalization.
- Cleanup of abandoned temporary files.

**Accept**
- Scanned and imported pages enter the same page model.
- Re-reading the page does not depend on an expired external temporary URI.
- Failure does not leave a partially registered document.

---

## 05 — EDITOR-001
**Model:** GPT-6.1 Sol Medium  
**Goal:** Build single-page preview/edit controls.

**Deliver**
- Page preview.
- Rotate.
- Adjust crop/re-crop using the smallest reliable local solution.
- Non-destructive edit state.
- Undo/reset to source for the supported edits.

**Accept**
- Rotation/crop survive leaving and returning to the editor during the session.
- Reset restores the source view.
- Large photos remain usable without obvious UI blocking.

---

## 06 — FILTER-001
**Model:** GPT-6.1 Sol Medium  
**Goal:** Add V1 document filters.

**Deliver**
- Original, Auto, Clean, B&W, Color.
- Deterministic local processing.
- Preview strategy that does not repeatedly process full-resolution data on every UI rebuild.
- Full-quality render path for export.

**Accept**
- Filters visibly improve representative document samples as intended.
- No AI/generative reconstruction.
- No network processing.
- Memory use remains bounded for normal single-page editing.

---

## 07 — DOCUMENT-001
**Model:** GPT-6.1 Sol Low  
**Goal:** Implement multi-page document management.

**Deliver**
- Add scanned/imported page.
- Delete page.
- Drag/reorder pages.
- Page thumbnails.
- Stable page IDs/order.

**Accept**
- Add/delete/reorder works across at least 10 pages.
- Page list uses thumbnails rather than holding all full-resolution pages.
- Reordering cannot silently lose a page.

---

## 08 — EXPORT-001
**Model:** GPT-5.6 Terra  
**Goal:** Export a page/document as JPG or PNG.

**Deliver**
- JPG output with sensible quality handling.
- PNG output.
- Safe generated filenames.
- Export uses current edit/filter state without overwriting source files.

**Accept**
- Output opens in another app.
- Dimensions/orientation are correct.
- Export failure preserves the saved document.

---

## 09 — PDF-001
**Model:** GPT-6.1 Sol Low  
**Goal:** Generate a multi-page PDF locally.

**Deliver**
- PDF pages in document order.
- Correct orientation/aspect handling.
- Bounded-memory generation strategy.
- Progress/error state.

**Accept**
- 10-page test document exports in correct order.
- PDF opens in a standard Android PDF viewer.
- Export does not require cloud/network processing.

---

## 10 — SHARE-001
**Model:** GPT-5.6 Terra  
**Goal:** Save/exported files and share them safely.

**Deliver**
- System share sheet.
- Platform-safe content URI/file sharing.
- User-visible save/export flow.
- MIME type handling for PDF/JPG/PNG.

**Accept**
- PDF and image share successfully to at least one external app.
- Private filesystem paths are not exposed as raw public paths.
- Cancelled share/save does not corrupt the document.

---

## 11 — HISTORY-001
**Model:** GPT-6.1 Sol Low  
**Goal:** Persist local documents and recent history.

**Deliver**
- SQLite metadata repository.
- Recent document list with thumbnail/date/title.
- Reopen document with page order and edit metadata.
- Delete document plus owned working files.

**Accept**
- Documents survive app restart.
- Reopened page order/edit state is correct.
- Deletion does not remove unrelated files.

---

## 12 — QA-001
**Model:** GPT-5.6 Terra  
**Goal:** Complete automated regression coverage.

**Deliver**
- Unit tests for document/page state and repositories.
- Widget tests for key local flows where practical.
- Export logic tests using deterministic fixtures.
- Static analysis cleanup limited to project code.

**Accept**
- `flutter analyze` passes.
- Automated test suite passes.
- No unrelated refactor solely to increase test coverage.

---

## 13 — QA-002
**Model:** GPT-6.1 Sol Medium  
**Goal:** Validate Android runtime, memory, and failure paths.

**Test**
- camera/scan success and cancel
- gallery success and cancel
- unsupported/unavailable scanner handling
- activity/background/resume behavior
- multi-page editing
- large image handling
- 10+ page PDF export
- low/revoked permission cases where applicable
- temp-file cleanup
- share/save flows

**Accept**
- No reproducible crash in required V1 flows.
- No obvious unbounded bitmap/page memory retention.
- Known device-specific limitations are documented rather than hidden.

---

## 14 — RELEASE-001
**Model:** GPT-6.1 Sol Low  
**Goal:** Produce an Android V1 release candidate.

**Deliver**
- Release build succeeds.
- App metadata/versioning ready for testing distribution.
- Dependency and permission review.
- Debug logging/developer-only behavior removed from release.
- Secret/signing material remains outside source control.
- Privacy/data-use notes reflect the actual implementation.

**Accept**
- Release artifact installs and launches on a real Android device.
- Smoke test covers scan/import -> edit -> multi-page -> save/reopen -> export/share.
- All previous task acceptance criteria remain satisfied.
- V1 contains no Account, Cloud Sync, OCR, AI Deblur, or AI Super Resolution.
