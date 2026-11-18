# AI removal inventory and validation

Conversation removal was committed as `00f1a3d1`; CLI provider removal as `acdf0de9`.
The earlier checkpoint sections below are historical snapshots. See [Final validation](#final-validation)
for the current state and outstanding checks.

## Traced ownership and entry points

Before removal, `App/AppCore.swift` owned `ChatHistoryStore`, `AIChatSurfacesState`,
`ChatPresetStore`, `AIChatCoordinator` and `QuickAICoordinator`. Startup applied the chat flag,
loaded presets/history lazily, and applied MCP. Termination reset chats and stopped Codex,
installed probes, MCP connections and OAuth. `trackChatRoute` projected live chat routes into MCP.
`Features/Settings/SettingsEditorPresenter.swift` injected chat/preset/MCP dependencies; the
palette reached them through its injected core (`Palette/PaletteEnvironment.swift`).

Conversation UI (all under `Tinycast/Features/AI/UI/`): `AIScreen.swift`,
`QuickAICoordinator.swift`, `AIChatCoordinator.swift`, `AIChatState.swift`,
`AIChatSurfacesState.swift`, `AIChatSplitViewController.swift`, `AIChatWindowChrome.swift`,
`AIChatSidebarView.swift`, `AIChatDetailView.swift`, `AIEmptyState.swift`,
`ChatHistoryScreen.swift`, `ChatHistoryView.swift`, `ChatTranscriptView.swift`,
`ChatComposerTextView.swift`, `ChatComposerChips.swift`, `ChatAttachmentReader.swift`,
`ChatSuggestionChips.swift`, `ChatFindState.swift`,
`ChatTextHighlight.swift`, `AIModelMenu.swift`.

External entry-point files under `Tinycast/`:
- `Features/Launcher/Model/{CommandID,CommandCatalog,Fallback}.swift` and
  `Features/Launcher/UI/{LauncherCoordinator,FallbackCoordinator}.swift`: Quick AI
  (`command:ai-chat`), AI Chat (`command:ai-chat-window`), Ask Quick AI fallback.
- `Palette/{RootPaletteView,PaletteMode,PaletteTabAction,PaletteFilterAction,PaletteWindowController}.swift`
  and the palette menu/shortcut declarations: screens, Tab, model/attachment menus, paste and chords.
- `Features/HotKeys/Model/HotKeyAction.swift`: command-derived bindings (no separate chat action).
- `Features/DeepLinks/Model/{DeepLink,DeepLinkConsentPolicy}.swift` and
  `Features/DeepLinks/UI/DeepLinkCoordinator.swift`: command links, chat UUID links and draft filling.
- `App/{AppCore,TinycastApp}.swift`: reopen, menu close-window routing, lifecycle and observers.
- `Features/Settings/{SettingsAnchor,SettingsSearchCatalog,SettingsFileSchema}.swift`,
  `Features/Settings/Model/SettingsFileKey.swift`: conversation search/file metadata.

## Settings: UI → store → persisted key → consumers

Removed from `Features/AI/Settings/AISettingsView.swift` and `AISettingsStore.swift`:

| UI / property | UserDefaults key | Former consumers |
| --- | --- | --- |
| Enable AI / `AppSettings.aiEnabled` | `aiEnabled` | chat lifecycle, launcher/Tab/fallback, MCP activation, installed-provider lifecycle |
| Default model / `defaultModel` | `aiDefaultModel` | new chat routing, picker fallback/reconciliation; Quick Actions already independent |
| Web search / `webSearchEnabled` | `aiWebSearch` | conversation requests/composer |
| Suggested replies / `choicesEnabled` | `aiChoices` | instruction composition and chips |
| Expand thinking / `expandsReasoning` | `aiExpandsReasoning` | transcript environment |
| System prompt / `systemPrompt`, `systemPromptEnabled` | `aiSystemPrompt`, `aiSystemPromptEnabled` | `AIInstructions` / `AIPreamble` |
| Keep conversations / `retention` | `aiRetentionDays` | coordinator → history prune/VACUUM |
| Opens to / `opensTo` | `aiOpensTo` | conversation open policy |
| Start new after / `newChatAfter` | `aiNewChatAfterMinutes` | conversation open policy |
| Tool rounds / `toolRounds` | `aiToolRounds` | conversation tool sessions |
| MCP UI / `mcpEnabled`, servers | `mcpEnabled`, `mcpServers` | MCP coordinator, connections, OAuth and tool dispatch |

Corresponding settings-file bindings, search anchors/catalog rows and backup metadata are removed.
Old defaults are inert, not erased or migrated. Preserve `ai-chats.sqlite3` (including sidecars)
and `chat-presets.json` in bundle-isolated Application Support: remove runtime readers/writers,
not user files. Preset editor/section and generated-title request/sanitizer runtime are removed.
No credentials are deleted, including provider keys/headers, installed environment values and MCP secrets.

## Retained boundary

AI pane remains provider-only and accessible independently of Quick Actions. Retain all seven
model sources: Apple Intelligence, Codex, Claude, Grok, OpenCode, Cursor and API connections.
`aiConnections`, `aiInstalledProviders`, `aiShownModels`, `aiDisabledRoutes`,
`aiInstalledOverrides` remain owned by `AISettingsStore`; provider management and Quick Action
pickers/factory consume them. Installed launch callbacks still read path/environment overrides;
Quick Actions owns discovery enablement and termination stops the managers. Provider management
may explicitly refresh them while open. No CLI provider removal at this checkpoint.

Retain Quick Action instructions/routes/overrides, Apple Translation, selectable Markdown,
syntax highlighting, math and copy behavior. Strip conversation find/citation rendering plumbing;
HTTP decoders retain their citation-link normalization helper without the transcript source model.
MCP app-owned settings/UI/connections can be removed; shared AI tool wire/session/CLI bridge
contracts remain until the CLI-removal checkpoint because existing providers compile against them.
The exact boundary is `AI/Model/{AITool,AIToolServer,JSONValue,CodexMCPLaunch,ClaudeMCPLaunch,
OpenCodeMCPLaunch,ClaudeControlProtocol}.swift`, tool-bearing `AIRequest`/stream models,
`AI/Service/{AIToolLoopProvider,OpenCodeMCPBridge}.swift`, and the existing CLI provider/turn-runner/
Codex-client tool branches. Quick Actions supplies no tool session/server, so none is armed by the
current app. All of `Features/MCP/`, its four app-owned lifecycle owners and its three harnesses and
two fixture servers are gone. `KeychainSecretStore.mcpSecrets`'s unused accessor is removed without
reading or deleting its saved scope.

`AI/UI/{ChatMarkdownText,ChatMarkdownRenderer}.swift`, `MarkdownBlock` and syntax/math
support remain Quick Action UI, not conversation state. The earlier claim that Extensions used
`ChatCopyButton` / `MarkdownCodeView` was incorrect: Extensions owns its renderer. Those orphan AI
views are removed in the dead-path checkpoint below. Shared field dictation tests now use a test-local
`NSTextView` rather than the deleted composer. Only the chat-switch/window teardown cases were
retired; field delivery, scoped cancellation, queued live delivery/cancellation and cue tests remain.
Unused window/composer/find theme tokens were removed; shared rendering/terminal spacing remains.

`Scripts/sync-strings.sh` now prunes only compiler-marked stale catalog entries after syncing,
preserving canonical formatting. Regeneration retired 276 keys, added none, and preserved every
surviving entry and translation exactly. The Xcode project was regenerated, not hand-edited.

## Progress / verification

Implementation complete; verification is partial due to the blockers below. Independent Quick
Action routing edits that predated this task remain in place. No commits or user-data cleanup were
performed. No manual UI verification has been performed.

Toolchain: the default `xcode-select` is CommandLineTools; full Xcode was discovered at
`/Applications/Xcode.app`. Commands that need it use
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

- `xcodegen generate`: exit 0.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/run-tests.sh`: exit 0,
  all **110** harnesses passed. Log: `/tmp/tinycast-conversation-tests.log`. After renaming the
  test-local editor, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/run-tests.sh
  DictationFieldTests` also passed (1/1; `/tmp/tinycast-conversation-dictation.log`).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Tinycast.xcodeproj
  -scheme Tinycast -configuration Debug CODE_SIGNING_ALLOWED=NO build`: exit 0. Log:
  `/tmp/tinycast-conversation-build.log`. AppIntents metadata extraction reports that there is no
  AppIntents.framework dependency; no Swift compilation warnings/errors were reported.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/lint.sh`: exit 2,
  **blocked: swiftlint is not installed**. Log: `/tmp/tinycast-conversation-lint.log`.
- `git diff --check`: exit 0.
- `node Scripts/check-settings-search.js`: exit 0.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/check-migrations.sh`: exit 0.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/sync-strings.sh`: build/sync
  and stale pruning completed; exit 1 at its localization check. `node Scripts/check-localizations.js`
  independently reports the same **18 pre-existing InfoPlist catalog errors**: `CFBundleName` and
  `NSHumanReadableCopyright` each have English state `new` and eight missing translations. That file
  is unchanged from HEAD. No surviving Localizable entry has a missing translation or stale marker.
  Logs: `/tmp/tinycast-conversation-{strings,localizations}.log`.

Follow-up: install SwiftLint and rerun lint; resolve the unchanged InfoPlist localization baseline;
perform the manual provider/Quick Action/Translation/removed-entry-point checks in `features/ai.md`.
CLI provider/tool contract deletion belongs to the next checkpoint, not this one.

## CLI provider removal checkpoint

Removed: Codex, Claude, Grok, OpenCode and Cursor — discovery/probes, subprocess and app-server
transports, launch/protocol/MCP-bridge files, tool-loop and tool contracts, the installed-provider and
Codex managers, their lifecycle wiring in `AppCore`, provider-panel sections, path/environment
overrides, the temporary `AIProviderDiscovery`, exclusive harnesses, brand assets (Cursor, Grok,
OpenCode) and `Features/MCP` documentation. HTTP effort labels were extracted to
`AI/Model/AIEffort.swift` first. Retained: direct HTTP connections, Foundation Models, Apple
Translation, shared Markdown and citation helpers, and unrelated subprocess features.

Untouched on disk and unread: `aiInstalledProviders`, `aiInstalledOverrides`, the
`installed-ai-environment` and `mcp-secrets` Keychain scopes, `ai-chats.sqlite3`, `chat-presets.json`
and the old workspace folders. `ai-api-keys` and `ai-request-headers` remain live.

Policy: a saved CLI selection no longer decodes. A retired shared route resolves like an unset one
(enabled, available Apple Intelligence, otherwise an explicit choice, never HTTP automatically); a
retired override is dropped so its action follows the shared route; overrides decode entry by entry,
so valid HTTP overrides and their efforts survive restart without any migration.
`QuickActionTests.retiredSelectionsRequireIndependentResolution` pins this.

T5 is documented only as a future possibility in `features/ai.md`.

## Final validation

Validated on 2026-11-18 after `acdf0de9`, including the uncommitted Quick Actions Accessibility
indicator refresh (pane appearance and application activation). The user confirmed Accessibility
works after switching from ad-hoc signing to stable development signing. This confirms the reported
permission problem is resolved, not that the entire manual feature sweep has been performed.

- Full harness suite: **110/110 passed** (`/tmp/tinycast-final-tests.log`).
- Debug app build with signing enabled: **succeeded** (`/tmp/tinycast-final-build.log`). The resulting
  app has an Apple Development signature, not an ad-hoc signature. Only the existing AppIntents
  metadata-extraction warning was reported; no Swift compilation warnings or errors.
- `./Scripts/lint.sh`: blocked because SwiftLint is not installed (`/tmp/tinycast-final-lint.log`).
- Settings-search and migration checks: passed independently.
- Localization check: the same 18 existing errors in unchanged `InfoPlist.xcstrings`; no errors in
  `Localizable.xcstrings` (`/tmp/tinycast-final-localizations.log`).
- Model import purity scan: no AppKit, SwiftUI or Cocoa imports.
- Removed conversation/CLI runtime-symbol scan: no references found in shipped Swift sources.
- `git diff --check`: passed.
- Independent review found no actionable defects; focused Quick Action, HTTP/Responses and migration
  harnesses also passed during review.

No new feature work remains in this removal scope. Manual provider/Quick Action/Translation checks
listed in `features/ai.md` remain unverified unless separately confirmed by the user. Lint and the
InfoPlist localization baseline prevent claiming the repository's entire definition of done is green.
No model generation against real HTTP services or Foundation Models was exercised by this pass.

Local signing edits in the generated Xcode project were preserved, not regenerated or hand-edited
by this validation pass. They are not yet represented in `project.yml`; running XcodeGen may overwrite
them. Make the intended signing configuration reproducible through the project inputs or a documented
local override before relying on regeneration. The permission-indicator fix and these signing changes
were uncommitted at validation time; no commit was created by this pass.

## AI dead-path cleanup checkpoint

The subsequent cleanup removes only unreachable conversation-era provider/rendering paths:

- Deleted orphan `AI/UI/{MarkdownView,MarkdownInline,MarkdownCodeView,MarkdownTableView,ChatCopyButton}.swift`.
  No live callers remained. Extensions' independent `ExtensionMarkdownView` is unchanged.
- `AIRequest` now carries instructions, one text prompt and the output budget. Removed `AIMessage`,
  `AIImage`, `AIDocument`, attachment budgeting/multipart encoding and outbound web-search
  fields/capabilities/tools/plugins. Provider metadata and persisted settings remain untouched.
- Removed token/cost accounting and ignored usage/thinking/reasoning/search/finish events, native
  reasoning decoder fields, search-progress reconstruction and unread finish/stop/content-block fields.
  Streams emit answer text only. Leading `<think>` suppression, citations as safe deduplicated text
  links, terminal framing, truncation failures, provider errors/redaction and cancellation remain.
- Removed test-only failed-tail rendering and on-device history reconstruction. Instructions,
  permissive transformation guardrails, output limits and live reasoning-effort requests remain.
  The context-limit error reuses the existing translated selection-too-long key.
- Kept `ChatMarkdownText` / `ChatMarkdownRenderer`, Markdown parsing, code copy, math and syntax.
  Tests cover every three-part think-tag fragmentation and every prefix at DONE/EOF, ignored native
  reasoning/tool/usage frames, terminal states, HTTP formats, efforts, citations and active rendering.

Project handling: generated before/after projects in `/tmp/tinycast-ai-regen` and applied only their
source-removal delta to the working project (20 deletions). All `XCBuildConfiguration` objects were
compared before/after and remain exactly equal, preserving user signing. No generated project was
hand-edited; `project.yml` and Quick Actions' permission refresh are unchanged.

Verification uses `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for Xcode commands:

- `./Scripts/run-tests.sh`: **110/110 passed** (`/tmp/ai-all-tests.log`).
- `xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build`: signed build
  succeeded (`/tmp/ai-build.log`), with only the existing AppIntents metadata warning.
- Localization: `xcrun xcstringstool sync` consumed extraction data from that signed build, then the
  existing `sync-strings.sh` stale-pruning code ran. No unsigned build or artifact replacement was
  used. Two obsolete keys retired, no new keys; every surviving translation is unchanged.
- `./Scripts/lint.sh`: exit 2, SwiftLint unavailable (`/tmp/ai-lint.log`).
- `node Scripts/check-settings-search.js` and `./Scripts/check-migrations.sh`: passed independently.
- `node Scripts/check-localizations.js`: the same 18 baseline errors in unchanged
  `InfoPlist.xcstrings`; no Localizable errors (`/tmp/ai-localizations.log`).
- Model import purity scan and `git diff --check`: passed.

No commits, persisted-data cleanup, real provider generation or manual UI sweep were performed.
The earlier closeout and signing warning above remain applicable; the signing overrides are still
not represented in `project.yml`.
