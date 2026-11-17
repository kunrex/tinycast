# MCP removal boundary

The app-owned MCP subsystem was removed with conversations: no server settings/editor, OAuth
browser/callback flow, connection manager, stdio/HTTP client, consent coordinator, startup,
observation or teardown wiring remains. Quick Actions never offered tools and still does not.
Old `mcpEnabled`/`mcpServers` defaults and Keychain secrets are left untouched and have no runtime
reader. Nothing starts a configured MCP server from those saved settings.

The installed CLI providers are deliberately retained at this checkpoint. Their shared AI tool
contracts remain under `Tinycast/Features/AI/`:

- `Model/AITool.swift`, `AIToolServer.swift`, `JSONValue.swift`, tool-bearing `AIRequest` and stream events;
- `Model/{CodexMCPLaunch,ClaudeMCPLaunch,OpenCodeMCPLaunch,ClaudeControlProtocol}.swift`;
- `Service/{AIToolLoopProvider,OpenCodeMCPBridge}.swift` and the tool branches of the installed
  providers, turn runners and Codex client.

These are compile-time dependencies of retained CLI providers and their tests, not a surviving
MCP product surface. The factory receives no tool session/server from Quick Actions, so these
contracts are never armed by the current app. Existing CLI deny/strict-config restrictions remain
important even with no Tinycast server. `AIProviderTests`, `AIResponsesTests` and `OpenCodeMCPTests`
continue testing those boundaries. App-owned MCP/OAuth/stdio harnesses and their unused fixture
servers are removed with that runtime.

Remove the shared CLI tool paths only during the subsequent CLI checkpoint, after tracing every
remaining transport/model dependency. No credentials or user CLI configuration were deleted or
rewritten by this removal. See [AI providers](ai.md) and the
[checkpoint inventory](../ai-removal-inventory.md).
