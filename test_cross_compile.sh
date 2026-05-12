#!/usr/bin/env bash
# Test script to verify cross-compilation works
set -e

echo "Testing cross-compilation to different targets..."

# Test cross-compiling to a different architecture
# This should succeed if manifest uses host target
echo "Test 1: Cross-compile to aarch64-linux"
zig build -Dtarget=aarch64-linux -Dzmpl_auto_build=false 2>&1 | tee /tmp/zmpl_cross_test.log

if grep -q "error" /tmp/zmpl_cross_test.log; then
    echo "❌ Cross-compilation test FAILED"
    exit 1
else
    echo "✅ Cross-compilation test PASSED"
    exit 0
fi
