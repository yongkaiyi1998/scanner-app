# ARCHITECTURE.md

## 1. Direction
A Flutter mobile document-scanner app with Android as the V1 target. The design should remain portable to iOS, but V1 must not be delayed by iOS parity.

Core principle: use mature platform scanning capabilities for document detection/correction, and keep app-owned code focused on document workflow, editing, persistence, and export.

## 2. V1 Technical Decisions
- UI/application: Flutter + Dart, stable channel.
- State management: Riverpod, kept feature-scoped; avoid a global “god” state object.
- Navigation: simple declarative routing; add a routing package only if it materially reduces complexity.
- Android scanning: Google ML Kit Document Scanner through a maintained Flutter package if one is reliable at implementation time; otherwise use a thin Kotlin platform-channel adapter.
- Gallery import: prefer Android system Photo Picker through a maintained Flutter integration.
- Local metadata: SQLite-backed storage through a small repository abstraction.
- Document files: app-private filesystem storage; do not store full images/PDF blobs inside SQLite.
- Export: generate JPG/PNG and multi-page PDF locally.
- Sharing: Android/iOS platform share sheet through a maintained Flutter package.
- Image filters: deterministic local processing in V1. Do not add AI models or OpenCV unless the filter task proves they are necessary.

Package versions are intentionally not frozen in this document. Verify current stable compatibility when each dependency is introduced.

## 3. Feature Layout
Use a small feature-first structure:

```text
lib/
  app/
  core/
    errors/
    files/
    utils/
  features/
    capture/
    scan/
    editor/
    documents/
    export/
    history/
```

Inside a feature, separate UI, state/controller logic, and data/platform adapters only when the separation is useful. Do not create empty layers for architectural purity.

## 4. Core Boundaries
Platform/native details must stay behind interfaces so UI code does not depend directly on Kotlin or plugin-specific types.

Suggested boundaries:

```text
DocumentScanner
PhotoImporter
DocumentRepository
DocumentFileStore
ImageProcessor
ExportService
ShareService
```

Implementations may use Flutter packages or Android native adapters.

## 5. Data Model
Minimum persisted concepts:

```text
Document
- id
- title
- createdAt
- updatedAt
- pages[]

DocumentPage
- id
- sourcePath
- workingPath
- sortOrder
- rotation
- filter
- crop/edit metadata as needed
```

Keep edits non-destructive where practical. Store metadata in the database and images in app-private files.

## 6. Processing Pipeline
```text
Camera / Gallery
    -> scanner/import result
    -> validate URI/file
    -> copy required source into app-private working storage
    -> normalize orientation
    -> page editor metadata
    -> preview/thumbnails
    -> local export renderer
    -> JPG / PNG / PDF
    -> explicit Save / Share
```

Do not depend on temporary third-party URIs after import if long-term reopening requires the file.

## 7. Scanner Strategy
ML Kit Document Scanner is the preferred Android V1 scanner because it already provides a scanning flow with document detection and correction. Use its result as the normal path rather than implementing custom edge detection and perspective CV from scratch.

The scanner may depend on components delivered through Google Play services. Handle first-use initialization/download failure and unsupported-device errors as normal product states.

Do not hard-code an old Android minimum SDK from this document. At implementation time, choose the highest minimum required by current Flutter/plugin/ML Kit dependencies and document the resulting supported-device range.

## 8. Editor Strategy
V1 editor operations:
- Preview.
- Rotate.
- Re-crop/adjust crop if supported by the chosen local editor path.
- Auto, Clean, B&W, and Color document filters.
- Add/delete/reorder pages.

Filters must be predictable document-processing operations, not generative reconstruction.

## 9. Storage Lifecycle
- Imported/scanned sources needed for reopening are copied to app-private storage.
- Thumbnail/cache files are replaceable and may be regenerated.
- Deleting a document deletes only files owned by that document after confirmation.
- Exported user files are separate from internal working files.
- Temporary/intermediate files should be cleaned on success, cancellation, and recoverable failure where safe.

## 10. Performance
- Generate thumbnails for page lists instead of rendering full-resolution images.
- Decode images near the size needed for display/processing when possible.
- Process/export pages sequentially or in bounded batches.
- Avoid retaining multiple full-resolution bitmaps in memory.
- Long image/PDF work must expose progress and cancellation where practical.
- Test realistic multi-page documents on a mid-range Android device.

## 11. Error Model
Translate plugin/native exceptions into app-level error types such as:
- permission/cancelled
- scanner unavailable/unsupported
- import unreadable
- storage failure
- processing failure
- export/share failure

UI should show a recoverable action when one exists; raw stack traces must not be shown to users.

## 12. Future Extension Points
Not implemented in V1, but current boundaries should allow later addition of:
- iOS scanner implementation
- OCR
- AI deblur/super-resolution
- cloud sync/accounts

Do not add their dependencies, screens, database tables, or networking in V1.
