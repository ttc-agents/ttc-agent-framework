#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
swiftc -parse-as-library -o "$DIR/AgentLauncher" "$DIR/AgentLauncher.swift" -framework SwiftUI -framework AppKit
mkdir -p "$DIR/AgentLauncher.app/Contents/MacOS"
cp "$DIR/Info.plist" "$DIR/AgentLauncher.app/Contents/"
cp "$DIR/AgentLauncher" "$DIR/AgentLauncher.app/Contents/MacOS/"
codesign -s - --force --deep "$DIR/AgentLauncher.app"
echo "Built and signed: $DIR/AgentLauncher.app"
