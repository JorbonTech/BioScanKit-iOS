#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/bioscan-pending-checks.XXXXXX)"
trap 'rm -rf "$work"' EXIT
# 从生产模型提取 Foundation 值类型，避免为无 UI 的账本检查引入 SwiftUI/设备 SDK。
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root, work = map(Path, sys.argv[1:])
s = (root/'Sources/BioScanPaywall/PaywallModels.swift').read_text()
s = s[s.index('public struct CreditBalance:'):s.index('public enum BillingOperation:')]
(work/'CreditBalance.swift').write_text('import Foundation\n'+s)
PY
xcrun swiftc -module-cache-path /tmp/bioscan-pending-module-cache \
  "$work/CreditBalance.swift" \
  "$root/Sources/BioScanPaywall/CreditLedger.swift" \
  "$root/Sources/BioScanPaywall/PendingCreditPurchases.swift" \
  "$root/Tests/PendingCreditPurchasesChecks.swift" -o "$work/checks"
"$work/checks"
