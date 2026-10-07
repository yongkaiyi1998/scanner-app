# PRODUCT_SPEC.md

## Product Goal
Create a fast, simple mobile app that turns phone photos into clean document scans and exports them as images or PDF without requiring an account.

V1 is Android-first and local-first.

## Primary User Flow
```text
Home
  -> Scan Document OR Import from Gallery
  -> automatic document detection/correction
  -> Preview / Edit
  -> add more pages if needed
  -> reorder/delete pages
  -> save document locally
  -> export as PDF / PNG / JPG
  -> save or share
  -> reopen later from Recent Documents
```

## V1 Features

### Home / History
- `Scan Document` primary action.
- `Import from Gallery` secondary action.
- Recent local documents with title/date and thumbnail.
- Open an existing local document for editing/export.

### Capture / Import
- Launch Android document scanning flow.
- Import an existing image through the system picker.
- Graceful handling of cancellation, unavailable scanner, unreadable file, and denied/revoked access.

### Automatic Document Result
Normal scan flow should produce a document-like page with:
- detected/cropped document area
- perspective correction
- corrected orientation where available
- no surrounding desk/background in the final page

The user should be able to adjust/re-crop when the automatic result is wrong.

### Editor
Per-page actions:
- rotate
- adjust crop/re-crop
- Original
- Auto
- Clean
- B&W
- Color

`Auto` optimizes readability with deterministic image processing.
`Clean` aims for a whiter, more scan-like paper background.
`B&W` prioritizes high-contrast text.
`Color` keeps meaningful color while improving document readability.

V1 filters must never invent text or document details.

### Multi-page Documents
- Add another scanned/imported page.
- Delete a page.
- Drag/reorder pages.
- Preserve page order after closing/reopening the app.

### Export
Supported output:
- JPG
- PNG
- multi-page PDF

User chooses output type and filename. Export failure must not damage the saved document.

### Save / Share
- Save exported output through platform-supported storage flow.
- Share exported output using the system share sheet.
- Never expose an internal private path as if it were a public file.

### Local History
- Documents persist locally without login.
- Reopening restores page order and edit state.
- User can delete a saved document and its app-owned working files.

## Privacy Expectations
- No account in V1.
- No cloud synchronization.
- User document contents are not intentionally uploaded for processing.
- A platform scanner component may require Google Play services to download scanner logic/components on first use; the app should communicate a recoverable error if initialization is unavailable.
- No document-content analytics or telemetry in V1.

## Non-Goals for V1
Explicitly excluded:
- OCR / selectable text
- AI deblur
- AI super-resolution
- generative image reconstruction
- cloud sync
- account/login
- collaboration
- annotations/signatures
- password-protected PDFs
- web/desktop app
- full iOS feature parity

These require a new approved scope before implementation.

## V1 Quality Bar
A V1 candidate is ready for release testing when:
- a real Android device can scan/import, edit, create multi-page documents, reopen them, export PDF/PNG/JPG, and share/save outputs;
- normal cancellation/error paths do not crash;
- a realistic multi-page document does not cause obvious memory failure;
- temporary/private files follow the intended lifecycle;
- automated checks pass;
- release build succeeds;
- no V2 feature or network upload was introduced accidentally.
