# AGENTS.md

## Purpose
This file defines how Codex should work in this repository. Product behavior belongs in `PRODUCT_SPEC.md`; technical structure belongs in `ARCHITECTURE.md`; task scope and status belong in `TASKS.md`.

## Working Rules
1. Work on one task from `TASKS.md` at a time.
2. Read only the documents and source files needed for the current task. Do not repeatedly scan the whole repository without a concrete reason.
3. Inspect the existing implementation before changing it. Reuse established patterns when they are sound.
4. Keep the diff scoped. Do not perform unrelated refactors, renames, dependency upgrades, formatting sweeps, or architecture changes.
5. Prefer the smallest maintainable solution that satisfies the acceptance criteria. Do not build V2 features early.
6. Do not start the next task automatically.
7. Ask for escalation only when a decision materially changes product behavior, architecture, security, data loss risk, or task scope. Normal implementation choices within an approved task do not require repeated approval.
8. Never use destructive Git commands, discard user changes, rewrite history, or delete unrelated files.

## Usage Efficiency
- Prefer targeted search and targeted file reads over repository-wide exploration.
- Do not reopen large generated/build files unless required.
- Avoid speculative abstractions and “future-proofing” that the current task does not need.
- Add a dependency only when the platform/Flutter SDK or existing dependencies cannot solve the problem cleanly.
- Run the narrowest useful tests while iterating; run the task’s full required checks before completion.
- If blocked, diagnose the smallest failing layer first. Do not attempt a broad rewrite as the first fix.
- Keep comments and documentation focused on non-obvious decisions; do not narrate obvious code.
- Do not duplicate requirements from the project docs into source comments.

## Security and Privacy
This app handles potentially sensitive documents.

- V1 is local-first. Do not upload document images, PDFs, metadata, or extracted content to a server unless a future approved task explicitly introduces networking.
- Do not add analytics, ads, crash attachment uploads, telemetry containing document data, or third-party cloud processing in V1.
- Never log image bytes, document contents, filenames supplied by users, share payload contents, or sensitive absolute paths in release logs.
- Never commit API keys, signing credentials, secrets, keystores, service-account files, or private configuration.
- Use least-privilege Android permissions. Prefer system pickers and scoped/app-private storage; do not request broad storage access unless technically necessary and explicitly approved.
- Treat imported files/URIs as untrusted input. Validate readable type, handle missing/revoked access, sanitize generated filenames, and prevent path traversal.
- Keep working files inside app-private storage or temporary directories. Clean temporary files when they are no longer needed.
- Exports must be explicit user actions. Sharing must use platform-safe content URIs/share APIs rather than exposing private filesystem paths.
- Preserve originals where practical and make edits non-destructive so a failed operation does not destroy the only copy.
- Use maintained dependencies from reputable publishers. Before adding one, check current maintenance status, platform support, license, and security advisories.
- Release builds must not expose debug-only logs or developer menus.

## Flutter / Android Quality Rules
- Keep UI responsive; do not decode/process full-resolution multi-page images on the UI thread when work can be bounded, streamed, resized, cached, or moved off-thread.
- Do not keep all full-resolution pages in memory simultaneously.
- Handle Android activity recreation, cancellation, permission denial, scanner unavailability, missing files, low-memory conditions, and interrupted exports without crashing.
- Use typed models and explicit error states rather than silent failure.
- Add tests around business logic and file/document state. Native scanning behavior must also be verified on a real Android device.
- Respect current Flutter/Dart lints and null safety.

## Dependency / Version Policy
- Use the current stable Flutter SDK selected for the project.
- Do not pin old package versions merely to match examples found online.
- Before changing Android SDK/Gradle/Kotlin requirements, verify the current official Flutter and dependency requirements.
- Prefer first-party platform APIs or mature maintained packages over custom native code. Use a small Kotlin bridge only where Flutter packages are insufficient.

## Completion Report
For each task, report only:
1. What changed.
2. Files changed.
3. Tests/checks run and their results.
4. Any unresolved risk or manual test still required.
5. Whether the task acceptance criteria are fully met.

Do not claim a task is complete if required checks were skipped or failed.
