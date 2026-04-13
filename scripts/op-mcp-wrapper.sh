#!/bin/bash
# op-mcp-wrapper.sh — Resolves op:// env vars via 1Password CLI, then exec's the real MCP command.
# Usage: op-mcp-wrapper.sh <command> [args...]
# All env vars containing op:// references are resolved by `op run` before exec.
exec /opt/homebrew/bin/op run -- "$@"
