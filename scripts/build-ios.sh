#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/logs
xcodebuild -project diction-processor.xcodeproj -scheme lingual -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .local/DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build > .local/logs/swift-build.log 2>&1 || { tail -60 .local/logs/swift-build.log; exit 1; }
tail -3 .local/logs/swift-build.log
