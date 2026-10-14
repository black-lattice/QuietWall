#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d -t quietwall-check)"
trap 'rm -rf "$check_dir"' EXIT

# Preserve SwiftPM's module boundaries: app imports must not hide missing core imports.
# Only emit a temporary module interface; do not link an app or create .build artifacts.
target="$(uname -m)-apple-macosx13.0"
test_frameworks="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
test_libraries="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib"
xcrun swiftc -emit-module -parse-as-library -enable-testing -swift-version 5 \
    -target "$target" -module-name QuietWallCore \
    -emit-module-path "$check_dir/QuietWallCore.swiftmodule" Sources/QuietWallCore/*.swift
xcrun swiftc -typecheck -parse-as-library -swift-version 5 -target "$target" \
    -I "$check_dir" Sources/QuietWall/*.swift
xcrun swiftc -typecheck -parse-as-library -swift-version 5 -target "$target" \
    -I "$check_dir" -F "$test_frameworks" -I "$test_libraries" \
    -module-name QuietWallCoreTests Tests/QuietWallCoreTests/*.swift

# Execute the actual core XCTest cases with the Swift interpreter; no app is launched.
cat Sources/QuietWallCore/*.swift > "$check_dir/core-tests.swift"
for source in Tests/QuietWallCoreTests/*.swift; do
    sed '/^@testable import QuietWallCore$/d' "$source" >> "$check_dir/core-tests.swift"
done
cat >> "$check_dir/core-tests.swift" <<'SWIFT'
let suite = XCTestSuite(name: "QuietWallCore")
suite.addTest(PolicyTests.defaultTestSuite)
suite.addTest(CoverageTests.defaultTestSuite)
suite.addTest(SessionSnapshotTests.defaultTestSuite)
suite.run()
guard let result = suite.testRun, result.executionCount >= 27, result.hasSucceeded else { exit(1) }
SWIFT
xcrun swift -F "$test_frameworks" -I "$test_libraries" -L "$test_libraries" \
    -lXCTestSwiftSupport "$check_dir/core-tests.swift"
plutil -lint Resources/Info.plist
bash -n scripts/package.sh
git diff --check
