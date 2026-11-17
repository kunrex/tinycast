# AI providers

Tinycast's provider layer serves [Quick Actions](quick-actions.md). Settings → AI remains a
provider-only pane: **Providers → Manage…** opens the connection and installed-command manager.
There is no Quick AI launcher screen, AI Chat window, conversation history, chat presets,
generated conversation titles, chat deep links or conversation settings at this checkpoint.
Existing `ai-chats.sqlite3` files and sidecars and `chat-presets.json` stay untouched in the active
bundle's Application Support directory. Their old preferences are inert. See the exact
[removal inventory](../ai-removal-inventory.md).

## Routes retained at this checkpoint

| Route | Transport / account |
| --- | --- |
| Apple Intelligence | Foundation Models on device, no key or endpoint |
| Codex | installed `codex app-server`, user's own login |
| Claude | installed `claude -p`, user's own login |
| Grok | installed `grok`, user's own login |
| OpenCode | installed OpenCode 2 `opencode run --standalone` |
| Cursor | installed `agent -p --mode ask`, user's own login |
| OpenAI API | Responses at the direct OpenAI endpoint |
| Anthropic | Messages |
| Gemini | Google's OpenAI-compatible API |
| OpenRouter | OpenAI-compatible API |
| OpenAI Compatible | user-configured compatible endpoint |

CLI removal is a later checkpoint, not part of conversation removal. All five installed routes,
their model discovery, reasoning efforts, path overrides and Keychain-backed environment values
remain. Apple Translation remains independent of generation; Translate never builds an AI provider.

## Ownership and lifecycle

`AppCore` owns `AISettingsStore`, `ChatGPTSubscriptionManager` (the historical name for the Codex
manager), and `InstalledAIManager`. Startup wires each manager's `launchSettings` callback to the
store. Quick Actions applies installed-provider discovery when enabled. Opening provider management
also owns discovery independently of Quick Actions; closing it cancels probes and stops helpers unless
Quick Actions still needs them. Disabling Quick Actions leaves discovery running only while the manager
is open. No discovery starts at launch with both owners inactive, and termination always stops it.
Check Again/Refresh can reprobe a provider. Codex releases its resident helper after its idle delay.
No chat history or preset store is constructed or opened.

Quick Actions owns its shared model and per-action overrides. An unset/invalid route defaults only
to enabled, available Apple Intelligence, otherwise it requires an explicit choice. A configured
HTTP connection is never automatically selected. There is no conversation default or reconciliation.
`AIProviderFactory.make` validates the selected route and reads credentials only when needed;
Quick Actions requests permissive content-transformation guardrails on device.

## Provider management

The manager lists On This Mac, Installed and API Connections. Installed routes have individual
switches, off by default; the on-device model and API connections have route switches too.
`AISettingsStore.isRouteEnabled` is the shared answer. Off preserves configuration and credentials,
but removes the route from available pickers and makes the factory refuse it.

Overview reports status, account, installed executable and Codex usage when available. Models is
a checklist (`AIModelChecklist`, a reused `NSTableView` inside the Form). Untouched routes show
all current/future models; an explicit checklist filters the picker. No model is locked by a
conversation default. Installed routes' Advanced page stores an explicit command path and variable
names in `aiInstalledOverrides`; values live in `KeychainSecretStore.installedAIEnvironment`.
An explicit missing path fails rather than silently running another copy. Tinycast-managed
variables, `NO_COLOR` and `TC_MCP_` names cannot be overridden. Launch revisions recheck the edited
provider while Quick Actions is enabled. `ExecutableLocator` asks the login shell before PATH and
known install prefixes, and supplies a runnable environment to every probe/turn.

API connections store provider, endpoint and exact model identifiers in `aiConnections`.
Discovery is debounced and cacheless; manually entered exact identifiers remain supported for
partial catalogs and gateways. Reasoning efforts and Anthropic output limits belong to the endpoint
that declared them and are dropped on retargeting. `AIModelOption` and `AIModelSelectionRows` supply
Quick Actions' catalog and effort choices; `offeredEffort` rejects stale levels.

## Security and persistence

- API keys and custom request-header values stay only in the login Keychain, addressed by connection
  UUID. Changing an endpoint does not lend it the former endpoint's key. Explicitly removing a
  connection still removes its own key and headers; this checkpoint itself deletes no credentials.
- Remote endpoints require HTTPS; HTTP is allowed only on loopback. `AIEndpointPolicy` is shared.
- Every HTTP request uses a private ephemeral URLSession without a URL cache. Provider errors are
  bounded and secrets redacted by `AIProviderFailure`.
- Installed commands reuse their normal accounts; Tinycast does not read their credential files.
  Their existing tool restrictions, private workspaces and cleanup remain in place.
- Quick Actions offers no tools. The app-owned [MCP runtime](mcp.md) is removed. Shared AI tool
  wire/session contracts and CLI bridge/launch implementations remain for the later CLI checkpoint;
  they are not armed by any current application consumer.
- Provider metadata, disabled routes, shown models, installed overrides and Quick Action routes remain
  machine-local and excluded from settings backups. Conversation keys are no longer active settings
  or settings.json bindings. No migration deletes user-owned history or presets.

## Rendering and verification

Quick Action results retain `ChatMarkdownText` / `ChatMarkdownRenderer`: one selectable attributed
string with lists, tables, safe web/mail links, syntax-highlighted code, copy headers and native
LaTeX math. Conversation find paths, highlights and inserted citation-number rendering are gone.
`AICitationLinker` still normalizes HTTP citation annotations to Markdown without a transcript model.
Extensions also use `MarkdownView` and its shared copy button; that path remains.

Harnesses: `AIProviderTests`, `AIResponsesTests`, `OpenCodeMCPTests` (retained CLI contracts),
`AppleIntelligenceTests`, `ChatMarkdownTests`, `SyntaxHighlightTests`, `QuickActionTests` and
`TextDiffTests`. Real Apple Intelligence generation remains opt-in.

Manual follow-up: verify provider management with Quick Actions off/on, all retained routes and
reasoning efforts, text transformations and Markdown copying, Apple Translation, and absence of
conversation commands, Tab stops, links and settings. Automated builds do not establish UI behavior.
