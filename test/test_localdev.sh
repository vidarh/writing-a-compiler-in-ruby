#!/bin/bash
#
# Test suite for LOCALDEV — Docker-Free Local Compilation
#
# Validates that the unified compile/compile2 scripts work correctly
# with the local toolchain, that bin/setup-i386-toolchain works, and
# that Docker fallback is preserved.
#
# Usage: bash test/test_localdev.sh
#

set -u

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() {
    echo "PASS: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo "FAIL: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

skip() {
    echo "SKIP: $1"
    SKIP_COUNT=$((SKIP_COUNT + 1))
}

# Ensure we're in the project root
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

# Cleanup trap: restore toolchain if renamed
cleanup() {
    if [ -d toolchain/32root.bak ]; then
        rm -rf toolchain/32root
        mv toolchain/32root.bak toolchain/32root
    fi
    # Clean up temp test files
    rm -f /tmp/localdev_test_*.rb
    rm -f out/localdev_test_*
}
trap cleanup EXIT

########################################################################
# 1. File existence and permissions
########################################################################

if [ -x bin/setup-i386-toolchain ]; then
    pass "bin/setup-i386-toolchain exists and is executable"
else
    fail "bin/setup-i386-toolchain exists and is executable"
fi

if [ -x compile ]; then
    pass "compile exists and is executable"
else
    fail "compile exists and is executable"
fi

if [ -x compile2 ]; then
    pass "compile2 exists and is executable"
else
    fail "compile2 exists and is executable"
fi

if [ ! -e compile_local ]; then
    pass "compile_local deleted"
else
    fail "compile_local still exists (should be deleted)"
fi

if [ ! -e compile2_local ]; then
    pass "compile2_local does not exist"
else
    fail "compile2_local exists (should not)"
fi

########################################################################
# 2. .gitignore exception
########################################################################

if grep -q '!bin/setup-i386-toolchain' .gitignore; then
    # Verify it comes after bin/*
    BIN_LINE=$(grep -n 'bin/\*' .gitignore | head -1 | cut -d: -f1)
    EXCEPTION_LINE=$(grep -n '!bin/setup-i386-toolchain' .gitignore | head -1 | cut -d: -f1)
    if [ -n "$BIN_LINE" ] && [ -n "$EXCEPTION_LINE" ] && [ "$EXCEPTION_LINE" -gt "$BIN_LINE" ]; then
        pass ".gitignore has !bin/setup-i386-toolchain after bin/*"
    else
        fail ".gitignore has !bin/setup-i386-toolchain but NOT after bin/*"
    fi
else
    fail ".gitignore does not contain !bin/setup-i386-toolchain"
fi

if git ls-files bin/setup-i386-toolchain 2>/dev/null | grep -q setup-i386-toolchain; then
    pass "git tracks bin/setup-i386-toolchain"
else
    # May not be committed yet — check if it would be tracked
    if git ls-files --others --exclude-standard bin/setup-i386-toolchain 2>/dev/null | grep -q setup-i386-toolchain; then
        pass "git would track bin/setup-i386-toolchain (not yet committed)"
    else
        # It's not ignored, which is the important thing
        if git check-ignore bin/setup-i386-toolchain 2>/dev/null | grep -q setup-i386-toolchain; then
            fail "git ignores bin/setup-i386-toolchain"
        else
            pass "git does not ignore bin/setup-i386-toolchain"
        fi
    fi
fi

########################################################################
# 3. Makefile targets
########################################################################

if grep -q '^setup-toolchain:' Makefile; then
    pass "Makefile contains setup-toolchain target"
else
    fail "Makefile missing setup-toolchain target"
fi

if grep -q '^local-check:' Makefile; then
    pass "Makefile contains local-check target"
else
    fail "Makefile missing local-check target"
fi

if grep -q '\.PHONY.*setup-toolchain' Makefile; then
    pass "setup-toolchain is .PHONY"
else
    fail "setup-toolchain is not .PHONY"
fi

if grep -q '\.PHONY.*local-check' Makefile; then
    pass "local-check is .PHONY"
else
    fail "local-check is not .PHONY"
fi

if make -n setup-toolchain >/dev/null 2>&1; then
    pass "make -n setup-toolchain succeeds (syntax valid)"
else
    fail "make -n setup-toolchain fails"
fi

if make -n local-check >/dev/null 2>&1; then
    pass "make -n local-check succeeds (syntax valid)"
else
    fail "make -n local-check fails"
fi

########################################################################
# 4. bin/setup-i386-toolchain — toolchain population
########################################################################

# Run setup (it should be idempotent if already run)
if bin/setup-i386-toolchain >/dev/null 2>&1; then
    pass "bin/setup-i386-toolchain exits 0"
else
    fail "bin/setup-i386-toolchain exits non-zero"
fi

if [ -d toolchain/32root ]; then
    pass "toolchain/32root/ is populated"
else
    fail "toolchain/32root/ is not populated"
fi

# Check required files
for f in \
    toolchain/32root/lib/i386-linux-gnu/libc.so.6 \
    toolchain/32root/lib/i386-linux-gnu/ld-linux.so.2 \
    toolchain/32root/lib/i386-linux-gnu/libgcc_s.so.1 \
    toolchain/32root/usr/lib32/crt1.o \
    toolchain/32root/usr/lib32/crti.o \
    toolchain/32root/usr/lib32/crtn.o \
    toolchain/32root/usr/lib32/libc_nonshared.a \
; do
    if [ -e "$f" ]; then
        pass "$f exists"
    else
        fail "$f missing"
    fi
done

# Check crtbegin.o under any GCC version
CRTBEGIN=$(find toolchain/32root/usr/lib/gcc/x86_64-linux-gnu -name crtbegin.o -path '*/32/*' 2>/dev/null | head -1)
if [ -n "$CRTBEGIN" ]; then
    pass "crtbegin.o found: $CRTBEGIN"
else
    fail "crtbegin.o not found under toolchain/32root/usr/lib/gcc/x86_64-linux-gnu/*/32/"
fi

CRTEND=$(find toolchain/32root/usr/lib/gcc/x86_64-linux-gnu -name crtend.o -path '*/32/*' 2>/dev/null | head -1)
if [ -n "$CRTEND" ]; then
    pass "crtend.o found: $CRTEND"
else
    fail "crtend.o not found under toolchain/32root/usr/lib/gcc/x86_64-linux-gnu/*/32/"
fi

# Validation summary is printed
OUTPUT=$(bin/setup-i386-toolchain 2>&1)
if echo "$OUTPUT" | grep -qi "validation\|found\|missing"; then
    pass "setup script prints validation summary"
else
    fail "setup script does not print validation summary"
fi

# Idempotent run
if bin/setup-i386-toolchain >/dev/null 2>&1; then
    pass "bin/setup-i386-toolchain idempotent (second run exits 0)"
else
    fail "bin/setup-i386-toolchain idempotent run failed"
fi

########################################################################
# 5. bin/setup-i386-toolchain — error handling
########################################################################

# Check the script contains validation logic
if grep -q 'libc.so.6\|crt1.o\|crtbegin.o' bin/setup-i386-toolchain; then
    pass "setup script contains file validation logic"
else
    fail "setup script missing file validation logic"
fi

if grep -q 'dpkg-deb\|apt-get' bin/setup-i386-toolchain; then
    pass "setup script checks for required tools (dpkg-deb/apt-get)"
else
    fail "setup script missing required tool checks"
fi

# Check idempotency message
OUTPUT=$(bin/setup-i386-toolchain 2>&1)
if echo "$OUTPUT" | grep -qi "already set up"; then
    pass "setup script detects existing valid toolchain"
else
    fail "setup script does not detect existing valid toolchain"
fi

########################################################################
# 6. GCC version detection
########################################################################

# Script should NOT hardcode GCC 8
if grep -E '/8/|gcc-8' bin/setup-i386-toolchain; then
    fail "setup script hardcodes GCC version 8"
else
    pass "setup script does not hardcode GCC version 8"
fi

HOST_GCC_VERSION=$(gcc -dumpversion | cut -d. -f1)
if echo "$CRTBEGIN" | grep -q "/$HOST_GCC_VERSION/"; then
    pass "crtbegin.o is under host GCC version ($HOST_GCC_VERSION)"
else
    fail "crtbegin.o is NOT under host GCC version ($HOST_GCC_VERSION)"
fi

########################################################################
# 7. Unified compile — local mode
########################################################################

# Create a temp test file
TMPTEST="/tmp/localdev_test_hello.rb"
echo 'puts "Hello localdev"' > "$TMPTEST"

OUTPUT=$(COMPILE_MODE=local ./compile "$TMPTEST" -I. 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "COMPILE_MODE=local ./compile test file succeeds"
else
    fail "COMPILE_MODE=local ./compile test file fails (exit $EXIT_CODE)"
fi

if echo "$OUTPUT" | grep -qi "local"; then
    pass "compile local mode output contains 'local'"
else
    fail "compile local mode output does not contain 'local'"
fi

BNAME=$(basename "$TMPTEST" .rb)
if [ -f "out/$BNAME" ]; then
    pass "compiled binary out/$BNAME exists"
    BINOUT=$(./out/$BNAME 2>&1)
    if echo "$BINOUT" | grep -q "Hello localdev"; then
        pass "compiled binary produces expected output"
    else
        fail "compiled binary output unexpected: $BINOUT"
    fi
else
    fail "compiled binary out/$BNAME does not exist"
    skip "compiled binary produces expected output (binary missing)"
fi

########################################################################
# 8. Unified compile — Docker fallback
########################################################################

if command -v docker >/dev/null 2>&1 && docker image inspect ruby-compiler-buildenv >/dev/null 2>&1; then
    OUTPUT=$(COMPILE_MODE=docker ./compile test/hello.rb -I. 2>&1)
    if [ $? -eq 0 ]; then
        pass "COMPILE_MODE=docker ./compile succeeds"
    else
        fail "COMPILE_MODE=docker ./compile fails"
    fi
    if echo "$OUTPUT" | grep -qi "docker"; then
        pass "compile docker mode output contains 'docker'"
    else
        fail "compile docker mode output does not contain 'docker'"
    fi
else
    skip "Docker fallback test (Docker not available or image not built)"
    skip "Docker mode output check (Docker not available)"
fi

########################################################################
# 9. Unified compile — auto-detect mode
########################################################################

OUTPUT=$(unset COMPILE_MODE; ./compile test/hello.rb -I. 2>&1)
if [ $? -eq 0 ]; then
    pass "auto-detect mode ./compile succeeds"
else
    fail "auto-detect mode ./compile fails"
fi

if echo "$OUTPUT" | grep -qi "local"; then
    pass "auto-detect mode selects local toolchain"
else
    fail "auto-detect mode does not select local toolchain"
fi

########################################################################
# 10. Unified compile — forced local without toolchain
########################################################################

if [ -d toolchain/32root ]; then
    mv toolchain/32root toolchain/32root.bak
fi

OUTPUT=$(COMPILE_MODE=local ./compile test/hello.rb -I. 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "COMPILE_MODE=local without toolchain exits non-zero"
else
    fail "COMPILE_MODE=local without toolchain should fail but exited 0"
fi

if echo "$OUTPUT" | grep -qiE "toolchain|32root|setup-i386-toolchain"; then
    pass "error message mentions toolchain/32root/setup-i386-toolchain"
else
    fail "error message does not mention toolchain: $OUTPUT"
fi

# Restore toolchain
if [ -d toolchain/32root.bak ]; then
    mv toolchain/32root.bak toolchain/32root
fi

########################################################################
# 11. Unified compile2 — local mode
########################################################################

# Ensure out/driver exists
if [ ! -f out/driver ]; then
    echo "NOTE: Building out/driver first (required for compile2)..."
    ./compile driver.rb -I . -g >/dev/null 2>&1
fi

if [ -f out/driver ]; then
    OUTPUT=$(COMPILE_MODE=local ./compile2 driver.rb -I . -g 2>&1)
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        pass "COMPILE_MODE=local ./compile2 succeeds"
    else
        fail "COMPILE_MODE=local ./compile2 fails (exit $EXIT_CODE)"
    fi

    if echo "$OUTPUT" | grep -qi "local"; then
        pass "compile2 local mode output contains 'local'"
    else
        fail "compile2 local mode output does not contain 'local'"
    fi

    if [ -f out/driver2 ]; then
        pass "out/driver2 exists after compile2"
    else
        fail "out/driver2 missing after compile2"
    fi
else
    skip "compile2 test (out/driver not available)"
    skip "compile2 local mode output (out/driver not available)"
    skip "out/driver2 exists (out/driver not available)"
fi

########################################################################
# 12. Unified compile2 — preserves 2>&1 redirect
########################################################################

if grep -q '2>&1' compile2; then
    pass "compile2 preserves 2>&1 redirect"
else
    fail "compile2 missing 2>&1 redirect"
fi

########################################################################
# 13. Unified compile — tgc.o caching
########################################################################

rm -f out/tgc.o

TMPTEST2="/tmp/localdev_test_cache1.rb"
echo 'puts 42' > "$TMPTEST2"
COMPILE_MODE=local ./compile "$TMPTEST2" -I. >/dev/null 2>&1

if [ -f out/tgc.o ]; then
    pass "out/tgc.o created on first compile"
    MTIME1=$(stat -c %Y out/tgc.o 2>/dev/null || stat -f %m out/tgc.o 2>/dev/null)
    sleep 1

    TMPTEST3="/tmp/localdev_test_cache2.rb"
    echo 'puts 43' > "$TMPTEST3"
    COMPILE_MODE=local ./compile "$TMPTEST3" -I. >/dev/null 2>&1

    MTIME2=$(stat -c %Y out/tgc.o 2>/dev/null || stat -f %m out/tgc.o 2>/dev/null)
    if [ "$MTIME1" = "$MTIME2" ]; then
        pass "out/tgc.o NOT recompiled on second compile (caching works)"
    else
        fail "out/tgc.o was recompiled on second compile (caching broken)"
    fi
else
    fail "out/tgc.o not created"
    skip "tgc.o caching test (tgc.o not created)"
fi

########################################################################
# 14. make selftest integration
########################################################################

if COMPILE_MODE=local make selftest >/dev/null 2>&1; then
    pass "make selftest passes with local toolchain"
else
    fail "make selftest fails with local toolchain"
fi

########################################################################
# 15. make selftest-c integration
########################################################################

if COMPILE_MODE=local make selftest-c >/dev/null 2>&1; then
    pass "make selftest-c passes with local toolchain"
else
    fail "make selftest-c fails with local toolchain"
fi

########################################################################
# 16. run_rubyspec compatibility
########################################################################

if [ -f spec/bug_ternary_expression_spec.rb ]; then
    OUTPUT=$(./run_rubyspec spec/bug_ternary_expression_spec.rb 2>&1)
    # The important thing is that compilation succeeded and the spec ran.
    # Some specs have known failures (the ternary bug), so we don't check
    # the exit code — we check that the compile step worked.
    if echo "$OUTPUT" | grep -qi "compilation successful\|compiled to"; then
        pass "run_rubyspec compiles successfully with unified compile"
    elif echo "$OUTPUT" | grep -qi "local"; then
        pass "run_rubyspec uses local toolchain"
    else
        fail "run_rubyspec fails with unified compile"
    fi
    # Also verify spec actually ran
    if echo "$OUTPUT" | grep -qiE "passed|failed|total"; then
        pass "run_rubyspec spec actually executed"
    else
        fail "run_rubyspec spec did not execute"
    fi
else
    skip "run_rubyspec test (spec/bug_ternary_expression_spec.rb not found)"
fi

########################################################################
# 17. COMPILE_MODE=docker passthrough in compile2
########################################################################

if grep -q '/tmp:/tmp' compile; then
    pass "compile contains /tmp:/tmp Docker volume mount"
else
    fail "compile missing /tmp:/tmp Docker volume mount"
fi

if grep -q '/tmp:/tmp' compile2; then
    fail "compile2 contains /tmp:/tmp (should NOT)"
else
    pass "compile2 does NOT contain /tmp:/tmp Docker volume mount"
fi

########################################################################
# 18. No compiler code changes
########################################################################

# Check that no .rb files in root or lib/core/ were modified
BRANCH_POINT=$(git merge-base HEAD master 2>/dev/null || echo "HEAD~10")
CHANGED_FILES=$(git diff --name-only "$BRANCH_POINT" 2>/dev/null || echo "")

COMPILER_CHANGES=""
if [ -n "$CHANGED_FILES" ]; then
    COMPILER_CHANGES=$(echo "$CHANGED_FILES" | grep -E '^\w+\.rb$|^lib/core/' || true)
fi

if [ -z "$COMPILER_CHANGES" ]; then
    pass "no compiler source (.rb) or lib/core/ files changed"
else
    fail "compiler source files changed: $COMPILER_CHANGES"
fi

########################################################################
# Summary
########################################################################

echo ""
echo "========================================"
echo "$PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
echo "========================================"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
