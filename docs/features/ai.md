# AI providers

Tinycast's provider layer serves [Quick Actions](quick-actions.md) only. Settings → AI is a
provider-only pane: **Providers → Manage…** opens the connection manager. There is no Quick AI
launcher screen, AI Chat window, conversation history, chat presets, generated titles, chat deep
links, MCP runtime or installed-command (CLI) provider. Existing `ai-chats.sqlite3` files and
sidecars, `chat-presets.json`, retired preferences and retired Keychain scopes stay untouched in the
active bundle's locations; nothing reads them. See the [removal inventory](../ai-removal-inventory.md).

## Routes

| Route | Transport / account |
| --- | --- |
| Apple Intelligence | Foundation Models on device, no key or endpoint |
| OpenAI API | Responses at the direct OpenAI endpoint |
| Anthropic | Messages |
| Gemini | Google's OpenAI-compatible API |
| OpenRouter | OpenAI-compatible API |
| OpenAI Compatible | user-configured compatible endpoint (including loopback servers) |

Generation is direct HTTP or Foundation Models; no subprocess is launched. Apple Translation is
independent: Translate never builds an AI provider.

A possible future route is a small on-device T5-style model for quick English transformations. It is
only a possibility: nothing is embedded, no dependency is added, and it would have to fit the existing
`AIProvider` interface to be considered.

## Ownership and lifecycle

`AppCore` owns `AISettingsStore`, which holds connections, shown models and disabled routes. Nothing
starts at launch for providers; `AIProviderFactory.make` validates the selected route and reads
credentials only when a request is made. A selected Apple Intelligence route that is disabled or
unavailable fails with its message rather than switching transport.

Quick Actions owns its shared model and per-action overrides. An unset or invalid shared route
defaults only to enabled, available Apple Intelligence, otherwise it requires an explicit choice. A
configured HTTP connection is never selected automatically. Quick Actions request permissive
content-transformation guardrails on device and offer no tools.

## Provider management

The manager lists On This Mac and API Connections. The on-device model and each connection have a
route switch; `AISettingsStore.isRouteEnabled` is the shared answer. Off preserves configuration and
credentials, but removes the route from pickers and makes the factory refuse it.

Models is a checklist (`AIModelChecklist`, a reused `NSTableView` inside the Form). Untouched routes
show all current and future models; an explicit checklist filters the picker.

API connections store provider, endpoint and exact model identifiers in `aiConnections`. Discovery is
debounced and cacheless; manually entered identifiers remain supported for partial catalogs and
gateways. Reasoning efforts (`AIEffort`) and Anthropic output limits belong to the endpoint that
declared them and are dropped on retargeting. `AIModelOption` and `AIModelSelectionRows` supply Quick
Actions' catalog and effort choices; `offeredEffort` rejects stale levels.

## Security and persistence

- API keys and custom request-header values stay only in the login Keychain, addressed by connection
  UUID. Changing an endpoint does not lend it the former endpoint's key. Explicitly removing a
  connection still removes its own key and headers.
- Remote endpoints require HTTPS; HTTP is allowed only on loopback. `AIEndpointPolicy` is shared.
- Every HTTP request uses a private ephemeral URLSession without a URL cache. Provider errors are
  bounded and secrets redacted by `AIProviderFailure`.
- Provider metadata, disabled routes, shown models and Quick Action routes are machine-local and
  excluded from settings backups.
- Saved selections that name a retired CLI route no longer decode. Quick Action overrides decode entry
  by entry, so valid HTTP overrides survive; a retired shared route resolves like an unset one.

## Rendering and verification

Quick Action results use `ChatMarkdownText` / `ChatMarkdownRenderer`: one selectable attributed string
with lists, tables, safe web/mail links, syntax-highlighted code, copy headers and native LaTeX math.
`AICitationLinker` normalizes HTTP citation annotations to Markdown, retaining HTTP(S)-only URL
safety and deduplication. Extensions use their own `ExtensionMarkdownView` in `ExtensionDetailView.swift`;
the orphan SwiftUI `MarkdownView`, inline/code/table views and `ChatCopyButton` are removed.

Requests carry instructions, one text prompt and an output budget, not history or attachments. No
outbound web-search tools/plugins or model capability switches remain. Streams emit answer text only;
native reasoning, tool/search progress and usage frames are ignored. Leading streamed `<think>` blocks
are suppressed across fragmentation and EOF, never surfaced as answer text. Citations still become
text links. Reasoning-effort request configuration stays live. Terminal framing, truncation detection,
provider errors and cancellation remain; stream completion is not a separate ignored event.

The on-device session starts with instructions only, preserving permissive transformation guardrails
and output limits. Its context-window error reuses the translated selection-too-long message. The
selectable renderer retains code copying, safe links, math and syntax but no failed-tail styling.
No persisted settings, history, presets or credentials are removed by this dead-path cleanup.

Harnesses: `AIProviderTests`, `AIResponsesTests`, `AppleIntelligenceTests`, `ChatMarkdownTests`,
`SyntaxHighlightTests`, `QuickActionTests` and `TextDiffTests`. Real Apple Intelligence generation is
opt-in.

Manual checks: provider management with Quick Actions off and on, HTTP routes and reasoning efforts,
text transformations and Markdown copying, Apple Translation, and absence of conversation commands and
CLI providers. Automated builds do not establish UI behavior.
