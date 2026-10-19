#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -module-cache-path "$PWD/.build" Sources/Message.swift Tests/main.swift -o .build/message-tests
.build/message-tests
swiftc -module-cache-path "$PWD/.build" Sources/ServerClock.swift Sources/AccountReader.swift Tests/account/main.swift -o .build/account-tests
DANMU_TEST_STATE="$PWD/.build/account-test-$(date +%s).json" .build/account-tests
swiftc -module-cache-path "$PWD/.build" Sources/ServerClock.swift Sources/AccountReader.swift Tests/latency/main.swift -o .build/latency-tests
DANMU_TEST_STATE="$PWD/.build/latency-test-$(date +%s).json" .build/latency-tests

# Regression: a local clock 45s behind/ahead must neither delay new messages
# nor filter them as pre-start history. Both cases use only synthetic CLI data.
DANMU_TEST_CLOCK_OFFSET=45 DANMU_TEST_STATE="$PWD/.build/clock-behind-$(date +%s).json" .build/latency-tests
DANMU_TEST_CLOCK_OFFSET=-45 DANMU_TEST_STATE="$PWD/.build/clock-ahead-$(date +%s).json" .build/latency-tests

# Sustained reception must release subprocess pipes and recover empty responses.
swiftc -module-cache-path "$PWD/.build" Sources/ServerClock.swift Sources/AccountReader.swift Tests/stability/main.swift -o .build/stability-tests
DANMU_TEST_STATE="$PWD/.build/stability-test-$(date +%s).json" .build/stability-tests
