# Tinycast

Native macOS menu-bar launcher and productivity app, built with SwiftUI and AppKit; runs as an accessory without a Dock icon.
Maintain the inherited architecture as features change; this file does not prescribe a feature inventory. Ignore `.pi/`.

## Layout and ownership

- **`Tinycast/App/AppCore.swift` owns long-lived application state through `AppCore.shared`; do not add competing singletons.**
- `Tinycast/App/TinycastApp.swift` declares the entry point and SwiftUI app; `AppDelegate.swift` starts the core and handles lifecycle callbacks.
- Wire services and cross-component callbacks in `AppCore.start()`; follow its termination path for teardown.
- `Tinycast/Palette/` owns the palette shell; `PaletteEnvironment.swift` injects the core and shared observable dependencies into SwiftUI.
- Route user actions through coordinators; existing views can use the injected core as a coordinator locator.
- `Tinycast/Features/` contains feature-local code, generally split into `Model/`, `Service/`, `UI/`, and `Settings/` when needed.
- `Model/` holds data and decisions; `Service/` holds effects and platform integration; `UI/` holds views/coordinators; `Settings/` holds configuration UI.
- **Keep AppKit, SwiftUI, and Cocoa imports out of `Features/*/Model/`; harnesses compile shipped model sources independently.**
- Some model stores also perform persistence; do not assume `Model/` means effect-free code. Inject environment inputs for testability.
- `Tinycast/DesignSystem/` owns shared visuals and theme tokens; `Tinycast/Platform/` owns shared system integration and lifetime helpers.
- `Tinycast/Windows/` owns non-palette AppKit presentation; `Tinycast/Migrations/` holds one-shot persisted-state migrations.
- `Tinycast/Resources/` holds bundled data/localization; `Tests/` holds standalone Swift harnesses, not an XCTest target.
- `Scripts/` owns generators and verification tooling; `website/` is separate from the native application.
- Shared static configuration, caches, and callbacks also exist outside the core; trace callers before changing their lifetime.
- For example, `Tinycast/DesignSystem/Interaction/Motion.swift` holds shared motion configuration; this is not a precedent for new global service owners.

## Non-negotiables

- Target macOS 26+ with Swift 6 and complete strict concurrency; check newer API availability against `project.yml` and the active SDK.
- **Edit `project.yml`, then run `xcodegen generate` and include `Tinycast.xcodeproj` changes; never hand-edit the generated project.**
- Do not introduce SwiftPM or `Bundle.module`; this is an Xcode application project.
- Never hand-edit generated sources/resources; locate their generator in `Scripts/` and regenerate them.
- Keep persisted data isolated by the active bundle identifier; follow `Tinycast/Platform/AppPaths.swift` so Debug cannot overwrite Release data.
- Put user-owned data in Application Support and refetchable data in Caches; read `docs/migrations.md` before removing or renaming persisted state.
- Reuse theme tokens and preserve existing appearance behavior unless a visual change is requested; keep feature-specific UI inside its owner.
- Before removing a subsystem, trace core ownership, environment injection, startup/teardown, persisted state, resources, and tests.

## Swift conventions

- Preserve local patterns and formatter/linter configuration; use Observation (`@Observable`), not `ObservableObject`.
- Keep UI-facing mutable state on `@MainActor`; keep short UI operations synchronous to preserve event ordering.
- Mark non-observable implementation state with `@ObservationIgnored`; inject concrete collaborators instead of adding a dependency container.
- Move blocking/heavy work off-main; give asynchronous work an owner, cancellation, and teardown.
- Revalidate cancellation, operation identity, and destination after suspension before applying results that may be stale.
- Avoid closure retain cycles; use unowned captures only when the owner's lifetime encloses the collaborator's lifetime.
- Localize SwiftUI literals directly and traveling strings with `String(localized:)`; follow `docs/standards.md` for catalog syncing and translations.

## Verification

Run these separately for code changes; harness success does not prove the app builds or lint passes:

```sh
./Scripts/run-tests.sh
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build
./Scripts/lint.sh
```

Build with no new warnings; report checks that could not run. Documentation-only changes do not require an app build.
Consult `docs/development.md` and `docs/signing.md` for toolchain and signing prerequisites.

## Read first

- `docs/architecture.md` before changing ownership, wiring, or lifecycle.
- `docs/standards.md` before writing Swift; detailed naming, comments, concurrency, and localization rules live there.
- `docs/ui.md` before adding or restyling views; `docs/testing.md` before declaring code changes complete.
- Relevant `docs/features/` documentation before changing subsystem internals; `CONTRIBUTING.md` for upstream contribution policy.

If this file disagrees with the source, verify the discrepancy and update this file.
