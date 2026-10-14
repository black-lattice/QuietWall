#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d -t quietwall-check)"
trap 'rm -rf "$check_dir"' EXIT

# Type-check without linking/building an application or creating .build artifacts.
for source in Sources/QuietWall/*.swift Sources/QuietWallCore/*.swift; do
    sed '/^import QuietWallCore$/d' "$source" > "$check_dir/$(basename "$source")"
done
xcrun swiftc -typecheck -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-macosx13.0" "$check_dir"/*.swift

# Execute the actual core XCTest cases with the Swift interpreter; no app is launched.
cat Sources/QuietWallCore/*.swift > "$check_dir/core-tests.swift"
for source in Tests/QuietWallCoreTests/*.swift; do
    sed '/^@testable import QuietWallCore$/d' "$source" >> "$check_dir/core-tests.swift"
done
cat >> "$check_dir/core-tests.swift" <<'SWIFT'
let suite = XCTestSuite(name: "QuietWallCore")
suite.addTest(PolicyTests.defaultTestSuite)
suite.addTest(CoverageTests.defaultTestSuite)
suite.run()
guard let result = suite.testRun, result.executionCount >= 14, result.hasSucceeded else { exit(1) }
SWIFT
test_frameworks="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
test_libraries="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib"
xcrun swift -F "$test_frameworks" -I "$test_libraries" -L "$test_libraries" \
    -lXCTestSwiftSupport "$check_dir/core-tests.swift"
plutil -lint Resources/Info.plist
bash -n scripts/package.sh
git diff --check
