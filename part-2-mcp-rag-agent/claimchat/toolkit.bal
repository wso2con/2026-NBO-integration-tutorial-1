// toolkit.bal
// Not needed: the chat agent uses the built-in ai:McpToolKit (see agent.bal),
// which manages its own MCP client internally and avoids the ballerina/mcp
// version skew that a hand-rolled ai:McpBaseToolKit implementation hits when
// this package resolves a different ballerina/mcp version than ballerina/ai
// was built against.
