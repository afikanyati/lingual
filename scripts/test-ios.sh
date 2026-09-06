#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/logs
xcodebuild test -project diction-processor.xcodeproj -scheme lingual \
  -destination "${LINGUAL_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}" \
  -derivedDataPath .local/DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  > .local/logs/ios-tests.log 2>&1
printf 'iOS simulator tests passed. Log: .local/logs/ios-tests.log\n'
