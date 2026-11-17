#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/bioscan-analytics-checks.XXXXXX)"
trap 'rm -rf "$work"' EXIT
swiftc -swift-version 5 -emit-library -emit-module -module-name PostHog \
  "$root/Tests/BioScanAnalyticsTests/PostHogStub.swift" -o "$work/libPostHog.dylib" -emit-module-path "$work/PostHog.swiftmodule"
swiftc -swift-version 5 -I "$work" -L "$work" -lPostHog -Xlinker -rpath -Xlinker "$work" \
  "$root/Sources/BioScanAnalytics/BioScanAnalytics.swift" \
  "$root/Sources/BioScanAnalytics/BioScanBehaviorEvent.swift" \
  "$root/Tests/BioScanAnalyticsTests/AnalyticsRegressionChecks.swift" -o "$work/checks"
"$work/checks"
"$work/checks" --disabled
