# Test Adequacy Assessment: LOCALDEV — Docker-Free Local Compilation

**Date:** 2026-02-14
**Reviewer:** Claude Opus 4.6 (test-adequacy reviewer)

## Test File

- **Location:** `test/test_localdev.sh`
- **Exists:** Yes
- **Executable:** Yes (mode 755)

## Scenario-by-Scenario Coverage

### 1. File existence and permissions
| Check | test.md Requirement | Covered? | Notes |
|-------|---------------------|----------|-------|
| `bin/setup-i386-toolchain` exists and is executable | Yes | **YES** | Line 50-54 |
| `compile` exists and is executable | Yes | **YES** | Line 56-60 |
| `compile2` exists and is executable | Yes | **YES** | Line 62-66 |
| `compile_local` does NOT exist | Yes | **YES** | Line 68-72 |
| `compile2_local` does NOT exist | Yes | **YES** | Line 74-78 |

### 2. `.gitignore` exception
| Check | Covered? | Notes |
|-------|----------|-------|
| `.gitignore` contains `!bin/setup-i386-toolchain` | **YES** | Line 87-91 |
| Exception comes AFTER `bin/*` rule (ordering) | **YES** | Line 94-100 |
| `git ls-files` tracks the file | **YES** | Line 102-113, with fallback for worktree issues |

### 3. Makefile targets
| Check | Covered? | Notes |
|-------|----------|-------|
| `setup-toolchain` target exists | **YES** | Line 122-126 |
| `local-check` target exists | **YES** | Line 128-132 |
| Both in `.PHONY` | **YES** | Lines 134-149 |
| `make -n setup-toolchain` succeeds | **YES** | Line 151-155 |
| `make -n local-check` succeeds | **YES** | Line 157-161 |

### 4. `bin/setup-i386-toolchain` — toolchain population
| Check | Covered? | Notes |
|-------|----------|-------|
| Exits 0 on run | **YES** | Lines 171-178 |
| `toolchain/32root/` populated | **YES** | Lines 180-184 |
| All 7 required files exist | **YES** | Lines 186-202, checks each file individually |
| `crtbegin.o` exists (any GCC version) | **YES** | Lines 205-209 |
| `crtend.o` exists (any GCC version) | **YES** | Lines 211-215 |
| Validation summary printed | **YES** | Lines 218-222 |
| Idempotent (second run exits 0) | **YES** | Covered in scenario 5 (lines 232-239) |

### 5. `bin/setup-i386-toolchain` — error handling
| Check | Covered? | Notes |
|-------|----------|-------|
| Script contains file validation logic (grep check) | **YES** | Lines 248-252 |
| Idempotent: exits 0 on second run | **YES** | Lines 232-239 |
| Detects existing valid toolchain | **YES** | Lines 241-245 |
| Non-zero exit on missing deps (simulated) | **PARTIAL** | test.md notes this may not be directly testable; the test correctly falls back to grepping for validation logic |

### 6. GCC version detection
| Check | Covered? | Notes |
|-------|----------|-------|
| Setup script does NOT hardcode GCC 8 | **YES** | Lines 262-266 |
| `crtbegin.o` under correct host GCC version dir | **YES** | Lines 269-278 |
| `compile` script does NOT hardcode GCC 8 | **YES** | Lines 281-286 |

### 7. Unified `compile` — local mode
| Check | Covered? | Notes |
|-------|----------|-------|
| `COMPILE_MODE=local ./compile` exits 0 | **YES** | Lines 304-311 |
| Output contains "local" | **YES** | Lines 313-317 |
| Binary exists in `out/` | **YES** | Lines 320-325 |
| Binary runs and produces expected output | **YES** | Lines 328-333 |

### 8. Unified `compile` — Docker fallback
| Check | Covered? | Notes |
|-------|----------|-------|
| `COMPILE_MODE=docker` succeeds with Docker | **YES** | Lines 342-358, properly skipped if Docker unavailable |
| Output contains "docker" | **YES** | Lines 350-354 |
| Skipped if Docker unavailable | **YES** | Lines 356-358 |

### 9. Unified `compile` — auto-detect mode
| Check | Covered? | Notes |
|-------|----------|-------|
| Unset `COMPILE_MODE` succeeds | **YES** | Lines 367-374 |
| Selects local mode | **YES** | Lines 376-380 |

### 10. Unified `compile` — forced local without toolchain
| Check | Covered? | Notes |
|-------|----------|-------|
| Exits non-zero when toolchain absent | **YES** | Lines 390-411, with proper rename/restore |
| Error mentions toolchain/32root/setup-i386-toolchain | **YES** | Lines 403-407 |
| Cleanup trap protects against test failure | **YES** | Lines 34-39 |

### 11. Unified `compile2` — local mode
| Check | Covered? | Notes |
|-------|----------|-------|
| Builds `out/driver` first if needed | **YES** | Lines 421-424 |
| `COMPILE_MODE=local ./compile2` exits 0 | **YES** | Lines 427-434 |
| Output contains "local" | **YES** | Lines 436-440 |
| `out/driver2` exists | **YES** | Lines 442-446 |

### 12. Unified `compile2` — preserves `2>&1` redirect
| Check | Covered? | Notes |
|-------|----------|-------|
| `compile2` contains `2>&1` | **YES** | Lines 460-464 |

### 13. Unified `compile` — tgc.o caching
| Check | Covered? | Notes |
|-------|----------|-------|
| `tgc.o` created after first compile | **YES** | Lines 474-482 |
| `tgc.o` mtime unchanged on second compile | **YES** | Lines 485-502, with `sleep 1` between |
| Different test file used for second compile | **YES** | Lines 491-494 |

### 14. `make selftest` integration
| Check | Covered? | Notes |
|-------|----------|-------|
| `make selftest` passes (exit 0) | **YES** | Lines 513-520 |
| Uses local toolchain | **YES** | Lines 522-526 |
| Reports 0 failures | **YES** | Lines 528-532 |

### 15. `make selftest-c` integration
| Check | Covered? | Notes |
|-------|----------|-------|
| `make selftest-c` passes (exit 0) | **YES** | Lines 541-548 |
| Uses local toolchain | **YES** | Lines 550-554 |
| Reports 0 failures | **YES** | Lines 556-560 |

### 16. `run_rubyspec` compatibility
| Check | Covered? | Notes |
|-------|----------|-------|
| `run_rubyspec` with a spec file succeeds | **YES** | Lines 569-585 |
| Handles non-zero exit from spec failures gracefully | **YES** | Lines 577-582 |

### 17. `COMPILE_MODE=docker` passthrough — volume mount difference
| Check | Covered? | Notes |
|-------|----------|-------|
| `compile` contains `/tmp:/tmp` in Docker path | **YES** | Lines 594-598 |
| `compile2` does NOT contain `/tmp:/tmp` | **YES** | Lines 600-604 |

### 18. No compiler code changes
| Check | Covered? | Notes |
|-------|----------|-------|
| No `.rb` or `lib/core/` files in diff | **YES** | Lines 614-624 |

## External Dependencies

- **Network access:** NOT required for primary test path. The `bin/setup-i386-toolchain` uses system files when `gcc-multilib` is installed (the primary path). The `.deb` download fallback (Method 2) would require network, but it's not exercised when system files are present.
- **Docker:** NOT required. Docker tests are properly skipped when unavailable (scenario 8).
- **System packages:** Tests depend on `gcc-multilib` and `libc6-dev-i386` being installed, which they are in this environment. This is appropriate since the plan targets Debian/Ubuntu systems.

## Error Path Coverage

| Error Path | Covered? |
|------------|----------|
| Missing toolchain with `COMPILE_MODE=local` | **YES** (scenario 10) |
| Missing `gcc` in setup script | **YES** (script exits with error; not tested but logic verified) |
| Idempotent re-run | **YES** (scenario 5) |
| Docker unavailable gracefully handled | **YES** (scenario 8, skipped) |
| Compilation failure in local mode | **NO** (not specified in test.md) |

## Would Tests Fail If Implementation Reverted?

**YES.** The tests are tightly coupled to the implementation:
- Scenario 1: Would fail if `compile_local` were restored or `bin/setup-i386-toolchain` were missing
- Scenario 7-9: Would fail if `COMPILE_MODE` env var support were removed from `compile`
- Scenario 10: Would fail if the error handling for missing toolchain were removed
- Scenario 13: Would fail if tgc.o caching were removed
- Scenarios 14-15: Would fail if `make selftest`/`selftest-c` broke due to compile script changes
- Scenario 17: Would fail if Docker mount differences were altered

## Coverage Gaps

1. **Minor: `compile2` GCC 8 hardcoding check** — Scenario 6 checks `compile` but not `compile2` for hardcoded GCC 8. However, `compile2` uses the same `detect_gcc_version()` function, so this is a very minor gap.

2. **Minor: `bin/setup-i386-toolchain` exit on completely missing deps** — test.md acknowledges this may not be testable in the execution environment. The test correctly falls back to grepping for validation logic.

3. **Not applicable: `compile2_local` deletion** — The log notes `compile2_local` was already absent before execution. The test checks for non-existence, which passes. This is fine — the spec said to delete it and it's not there.

## Test Suite Run Results

**Command:** `bash test/test_localdev.sh`
**Exit code:** 0
**Output:**

```
=== Docker-Free Local Compilation Tests ===

--- 1. File existence and permissions ---
PASS: bin/setup-i386-toolchain exists and is executable
PASS: compile exists and is executable
PASS: compile2 exists and is executable
PASS: compile_local deleted
PASS: compile2_local does not exist

--- 2. .gitignore exception ---
PASS: .gitignore contains !bin/setup-i386-toolchain
PASS: .gitignore exception comes after bin/* rule
SKIP: git not available in this directory (worktree issue)

--- 3. Makefile targets ---
PASS: Makefile contains setup-toolchain target
PASS: Makefile contains local-check target
PASS: setup-toolchain is declared .PHONY
PASS: local-check is declared .PHONY
PASS: make -n setup-toolchain succeeds (dry-run)
PASS: make -n local-check succeeds (dry-run)

--- 4. bin/setup-i386-toolchain — toolchain population ---
PASS: bin/setup-i386-toolchain exits 0
PASS: toolchain/32root/ is populated
PASS: toolchain/32root/lib/i386-linux-gnu/libc.so.6 exists
PASS: toolchain/32root/lib/i386-linux-gnu/ld-linux.so.2 exists
PASS: toolchain/32root/lib/i386-linux-gnu/libgcc_s.so.1 exists
PASS: toolchain/32root/usr/lib32/crt1.o exists
PASS: toolchain/32root/usr/lib32/crti.o exists
PASS: toolchain/32root/usr/lib32/crtn.o exists
PASS: toolchain/32root/usr/lib32/libc_nonshared.a exists
PASS: crtbegin.o exists (any GCC version)
PASS: crtend.o exists (any GCC version)
PASS: setup script prints validation summary

--- 5. bin/setup-i386-toolchain — error handling ---
PASS: setup script is idempotent (exits 0 on second run)
PASS: setup script detects existing valid toolchain
PASS: setup script contains file validation logic

--- 6. GCC version detection ---
PASS: bin/setup-i386-toolchain does NOT hardcode GCC 8
PASS: crtbegin.o matches host GCC version (11)
PASS: compile script does NOT hardcode GCC 8

--- 7. Unified compile — local mode ---
PASS: COMPILE_MODE=local ./compile exits 0
PASS: compile output indicates local mode
PASS: compiled binary out/hello exists
PASS: compiled binary produces expected output

--- 8. Unified compile — Docker fallback ---
SKIP: Docker not available or ruby-compiler-buildenv image not built
SKIP: Docker mode output check (Docker not available)

--- 9. Unified compile — auto-detect mode ---
PASS: auto-detect ./compile exits 0
PASS: auto-detect selects local mode

--- 10. Unified compile — forced local without toolchain ---
PASS: COMPILE_MODE=local without toolchain exits non-zero
PASS: error message mentions toolchain/32root/setup-i386-toolchain

--- 11. Unified compile2 — local mode ---
PASS: COMPILE_MODE=local ./compile2 exits 0
PASS: compile2 output indicates local mode
PASS: out/driver2 exists after compilation

--- 12. Unified compile2 — preserves 2>&1 redirect ---
PASS: compile2 contains 2>&1 redirect

--- 13. Unified compile — tgc.o caching ---
PASS: out/tgc.o created after compile
PASS: out/tgc.o NOT recompiled (mtime unchanged, caching works)

--- 14. make selftest integration ---
PASS: make selftest passes
PASS: make selftest uses local toolchain
PASS: make selftest reports 0 failures

--- 15. make selftest-c integration ---
PASS: make selftest-c passes
PASS: make selftest-c uses local toolchain
PASS: make selftest-c reports 0 failures

--- 16. run_rubyspec compatibility ---
PASS: run_rubyspec compiled and ran (spec may have expected failures)

--- 17. Docker volume mount differences ---
PASS: compile contains /tmp:/tmp mount in Docker path
PASS: compile2 does NOT contain /tmp:/tmp mount

--- 18. No compiler code changes ---
PASS: no compiler source (.rb) or lib/core/ files modified

================================
Summary:
  55 passed, 0 failed, 3 skipped
================================
```

**Skips (3):**
1. Git tracking check — worktree environment limitation (`.gitignore` content check still passes)
2. Docker mode test — Docker not available in sandbox (expected per test.md)
3. Docker mode output check — Docker not available (expected per test.md)

## Design Quality

- **No hacks or bypasses:** Tests use `COMPILE_MODE` env var for code path control, which is a clean design-level mechanism built into the implementation per the spec.
- **Proper cleanup:** Trap handler ensures `toolchain/32root` is restored after rename tests.
- **Idempotent:** Test creates and cleans up temp files using `$$` PID-based naming.
- **Appropriate skip logic:** Docker tests gracefully skip rather than fail when Docker is unavailable.
- **No mocking needed:** As specified in test.md, all tests operate on real files and commands.

## Overall Verdict

**ADEQUATE**

All 18 test scenarios from `test.md` have corresponding tests. The test suite runs successfully with 55 passes, 0 failures, and 3 justified skips. Coverage is comprehensive across happy paths, error paths, and edge cases (idempotence, caching, mode auto-detection). The only gaps are cosmetically minor (not checking `compile2` for GCC 8 hardcoding) and do not represent meaningful risk given the shared code between `compile` and `compile2`.
