# Test Adequacy Assessment: LOCALDEV — Docker-Free Local Compilation

**Date:** 2026-02-15
**Reviewer:** Claude Opus 4.6 (test-adequacy reviewer)

## Test File

- **Location:** `test/test_localdev.sh`
- **Exists:** Yes
- **Executable:** Yes

## Scenario-by-Scenario Coverage

### 1. File existence and permissions
| Check | test.md Requirement | Covered? | Test Lines |
|-------|---------------------|----------|------------|
| `bin/setup-i386-toolchain` exists and is executable | Yes | **YES** | 53-57 |
| `compile` exists and is executable | Yes | **YES** | 59-63 |
| `compile2` exists and is executable | Yes | **YES** | 65-69 |
| `compile_local` does NOT exist | Yes | **YES** | 71-75 |
| `compile2_local` does NOT exist | Yes | **YES** | 77-81 |

### 2. `.gitignore` exception
| Check | Covered? | Test Lines |
|-------|----------|------------|
| `.gitignore` contains `!bin/setup-i386-toolchain` | **YES** | 87-98 |
| Exception comes AFTER `bin/*` rule (ordering) | **YES** | 89-95 |
| `git ls-files` tracks the file (or is not ignored) | **YES** | 100-114, with fallback checks |

### 3. Makefile targets
| Check | Covered? | Test Lines |
|-------|----------|------------|
| `setup-toolchain` target exists | **YES** | 120-124 |
| `local-check` target exists | **YES** | 126-130 |
| `setup-toolchain` in `.PHONY` | **YES** | 132-136 |
| `local-check` in `.PHONY` | **YES** | 138-142 |
| `make -n setup-toolchain` succeeds | **YES** | 144-148 |
| `make -n local-check` succeeds | **YES** | 150-154 |

### 4. `bin/setup-i386-toolchain` — toolchain population
| Check | Covered? | Test Lines |
|-------|----------|------------|
| Exits 0 on run | **YES** | 161-165 |
| `toolchain/32root/` populated | **YES** | 167-171 |
| All 7 required files exist individually | **YES** | 174-188 |
| `crtbegin.o` exists (any GCC version) | **YES** | 191-196 |
| `crtend.o` exists (any GCC version) | **YES** | 198-203 |
| Validation summary printed | **YES** | 206-211 |
| Idempotent (second run exits 0) | **YES** | 214-218 |

### 5. `bin/setup-i386-toolchain` — error handling
| Check | Covered? | Test Lines |
|-------|----------|------------|
| Script contains file validation logic (grep) | **YES** | 225-229 |
| Script checks for required tools (dpkg-deb/apt-get) | **YES** | 231-235 |
| Detects existing valid toolchain (idempotency message) | **YES** | 238-243 |
| Non-zero exit on missing deps (simulated) | **N/A** | test.md acknowledges not directly testable; grep approach used |

### 6. GCC version detection
| Check | Covered? | Test Lines |
|-------|----------|------------|
| Setup script does NOT hardcode GCC 8 | **YES** | 250-254 |
| `crtbegin.o` under correct host GCC version dir | **YES** | 256-261 |
| Detected version matches `gcc -dumpversion` | **YES** | 256-261 (checks `$HOST_GCC_VERSION` against crtbegin path) |

### 7. Unified `compile` — local mode
| Check | Covered? | Test Lines |
|-------|----------|------------|
| `COMPILE_MODE=local ./compile` exits 0 | **YES** | 271-278 |
| Output contains "local" | **YES** | 280-284 |
| Binary exists in `out/` | **YES** | 286-298 |
| Binary runs and produces expected output | **YES** | 289-294 |

### 8. Unified `compile` — Docker fallback
| Check | Covered? | Test Lines |
|-------|----------|------------|
| `COMPILE_MODE=docker` succeeds with Docker | **YES** | 304-319 |
| Output contains "docker" | **YES** | 311-315 |
| Skipped if Docker unavailable | **YES** | 304, 317-319 |

### 9. Unified `compile` — auto-detect mode
| Check | Covered? | Test Lines |
|-------|----------|------------|
| Unset `COMPILE_MODE`, compile succeeds | **YES** | 325-330 |
| Auto-detect selects local mode | **YES** | 332-336 |

### 10. Unified `compile` — forced local without toolchain
| Check | Covered? | Test Lines |
|-------|----------|------------|
| Exits non-zero when toolchain absent | **YES** | 342-353 |
| Error mentions toolchain/32root/setup-i386-toolchain | **YES** | 355-359 |
| Toolchain restored after test | **YES** | 362-364 + cleanup trap at 38-46 |

### 11. Unified `compile2` — local mode
| Check | Covered? | Test Lines |
|-------|----------|------------|
| Builds `out/driver` first if needed | **YES** | 371-374 |
| `COMPILE_MODE=local ./compile2` exits 0 | **YES** | 377-384 |
| Output contains "local" | **YES** | 386-390 |
| `out/driver2` exists | **YES** | 392-396 |

### 12. Unified `compile2` — preserves `2>&1` redirect
| Check | Covered? | Test Lines |
|-------|----------|------------|
| `compile2` contains `2>&1` | **YES** | 407-411 |

### 13. Unified `compile` — tgc.o caching
| Check | Covered? | Test Lines |
|-------|----------|------------|
| `tgc.o` created after first compile | **YES** | 417-424 |
| `sleep 1` between compilations | **YES** | 426 |
| `tgc.o` mtime unchanged on second compile | **YES** | 428-437 |
| Different test file used for second compile | **YES** | 428-430 |

### 14. `make selftest` integration
| Check | Covered? | Test Lines |
|-------|----------|------------|
| `make selftest` passes (exit 0) | **YES** | 447-451 |

### 15. `make selftest-c` integration
| Check | Covered? | Test Lines |
|-------|----------|------------|
| `make selftest-c` passes (exit 0) | **YES** | 457-461 |

### 16. `run_rubyspec` compatibility
| Check | Covered? | Test Lines |
|-------|----------|------------|
| `run_rubyspec` with a spec file works | **YES** | 467-487 |
| Compilation step succeeds | **YES** | 472-478 |
| Spec actually executed | **YES** | 480-484 |

### 17. `COMPILE_MODE=docker` passthrough — volume mount difference
| Check | Covered? | Test Lines |
|-------|----------|------------|
| `compile` contains `/tmp:/tmp` in Docker path | **YES** | 493-497 |
| `compile2` does NOT contain `/tmp:/tmp` | **YES** | 499-503 |

### 18. No compiler code changes
| Check | Covered? | Test Lines |
|-------|----------|------------|
| No `.rb` or `lib/core/` files in diff | **YES** | 510-522 |

## External Dependencies

- **Network access:** NOT required for primary test path. The `bin/setup-i386-toolchain` uses `apt-get download` to fetch `.deb` packages, which requires network on the first run. However, after the toolchain is populated (which happens before the test scenarios), no further network access is needed. The idempotent second run skips downloading entirely.
- **Docker:** NOT required. Docker tests (scenario 8) are properly skipped when Docker is unavailable.
- **System packages:** Tests depend on `gcc` being installed and `apt-get`/`dpkg-deb` being available (Debian/Ubuntu). This is appropriate since the plan explicitly targets Debian/Ubuntu systems.

## Error Path Coverage

| Error Path | Covered? | Details |
|------------|----------|---------|
| Missing toolchain with `COMPILE_MODE=local` | **YES** | Scenario 10 — renames toolchain dir, verifies non-zero exit |
| Missing `gcc`/`dpkg-deb`/`apt-get` in setup script | **PARTIAL** | Script logic verified via grep (scenario 5), not simulated |
| Idempotent re-run (toolchain already exists) | **YES** | Scenario 4 (second run) + scenario 5 |
| Docker unavailable gracefully handled | **YES** | Scenario 8, correctly skipped |
| Incomplete toolchain (crtbegin.o missing) | **NO** | Not tested, but `compile` checks for this and would fail with clear error |

## Would Tests Fail If Implementation Reverted?

**YES.** The tests are tightly coupled to the implementation:

- **Scenario 1:** Would fail if `compile_local` were restored or `bin/setup-i386-toolchain` were missing
- **Scenarios 7-9:** Would fail if `COMPILE_MODE` env var support were removed from `compile`
- **Scenario 10:** Would fail if the error handling for missing toolchain were removed
- **Scenario 12:** Would fail if `2>&1` redirect were removed from `compile2`
- **Scenario 13:** Would fail if tgc.o caching were removed (Docker path recompiles every time)
- **Scenarios 14-15:** Would fail if `make selftest`/`selftest-c` broke due to compile script changes
- **Scenario 17:** Would fail if Docker mount differences were altered
- **Scenario 18:** Would catch unintended compiler source changes

## Coverage Gaps

1. **Minor: `compile`/`compile2` GCC 8 hardcoding check** — Scenario 6 only checks `bin/setup-i386-toolchain` for hardcoded GCC 8 references, not the `compile`/`compile2` scripts themselves. However, both scripts use `Dir.glob()` to dynamically find `crtbegin.o` rather than hardcoding any version, so this is a negligible gap.

2. **Minor: `bin/setup-i386-toolchain` failure on completely missing deps** — test.md acknowledges this may not be directly testable if packages are already installed. The test correctly falls back to grepping for validation logic. Acceptable per test.md guidance.

3. **Minor: Incomplete toolchain error path** — No test for what happens when the toolchain directory exists but is missing critical files (e.g., `crtbegin.o` present but `crt1.o` missing). Both `compile` and `compile2` check for this and would print a clear error, but this path isn't exercised by the tests.

None of these gaps represent meaningful risk to the implementation quality.

## Test Suite Run Results

**Command:** `bash test/test_localdev.sh`
**Exit code:** 0
**Output:**

```
PASS: bin/setup-i386-toolchain exists and is executable
PASS: compile exists and is executable
PASS: compile2 exists and is executable
PASS: compile_local deleted
PASS: compile2_local does not exist
PASS: .gitignore has !bin/setup-i386-toolchain after bin/*
PASS: git would track bin/setup-i386-toolchain (not yet committed)
PASS: Makefile contains setup-toolchain target
PASS: Makefile contains local-check target
PASS: setup-toolchain is .PHONY
PASS: local-check is .PHONY
PASS: make -n setup-toolchain succeeds (syntax valid)
PASS: make -n local-check succeeds (syntax valid)
PASS: bin/setup-i386-toolchain exits 0
PASS: toolchain/32root/ is populated
PASS: toolchain/32root/lib/i386-linux-gnu/libc.so.6 exists
PASS: toolchain/32root/lib/i386-linux-gnu/ld-linux.so.2 exists
PASS: toolchain/32root/lib/i386-linux-gnu/libgcc_s.so.1 exists
PASS: toolchain/32root/usr/lib32/crt1.o exists
PASS: toolchain/32root/usr/lib32/crti.o exists
PASS: toolchain/32root/usr/lib32/crtn.o exists
PASS: toolchain/32root/usr/lib32/libc_nonshared.a exists
PASS: crtbegin.o found: toolchain/32root/usr/lib/gcc/x86_64-linux-gnu/11/32/crtbegin.o
PASS: crtend.o found: toolchain/32root/usr/lib/gcc/x86_64-linux-gnu/11/32/crtend.o
PASS: setup script prints validation summary
PASS: bin/setup-i386-toolchain idempotent (second run exits 0)
PASS: setup script contains file validation logic
PASS: setup script checks for required tools (dpkg-deb/apt-get)
PASS: setup script detects existing valid toolchain
PASS: setup script does not hardcode GCC version 8
PASS: crtbegin.o is under host GCC version (11)
PASS: COMPILE_MODE=local ./compile test file succeeds
PASS: compile local mode output contains 'local'
PASS: compiled binary out/localdev_test_hello exists
PASS: compiled binary produces expected output
SKIP: Docker fallback test (Docker not available or image not built)
SKIP: Docker mode output check (Docker not available)
PASS: auto-detect mode ./compile succeeds
PASS: auto-detect mode selects local toolchain
PASS: COMPILE_MODE=local without toolchain exits non-zero
PASS: error message mentions toolchain/32root/setup-i386-toolchain
PASS: COMPILE_MODE=local ./compile2 succeeds
PASS: compile2 local mode output contains 'local'
PASS: out/driver2 exists after compile2
PASS: compile2 preserves 2>&1 redirect
PASS: out/tgc.o created on first compile
PASS: out/tgc.o NOT recompiled on second compile (caching works)
PASS: make selftest passes with local toolchain
PASS: make selftest-c passes with local toolchain
PASS: run_rubyspec compiles successfully with unified compile
PASS: run_rubyspec spec actually executed
PASS: compile contains /tmp:/tmp Docker volume mount
PASS: compile2 does NOT contain /tmp:/tmp Docker volume mount
PASS: no compiler source (.rb) or lib/core/ files changed

========================================
52 passed, 0 failed, 2 skipped
========================================
```

**Skips (2):**
1. Docker fallback test — Docker not available in sandbox environment (expected per test.md)
2. Docker mode output check — Docker not available (expected per test.md)

## Design Quality

- **No hacks or bypasses:** Tests use `COMPILE_MODE` env var for code path control, which is a clean design-level mechanism built into the implementation per the spec.
- **Proper cleanup:** Trap handler at line 38-46 ensures `toolchain/32root` is restored after rename tests and temp files are cleaned up.
- **Idempotent:** Test creates temp files in `/tmp/` with unique names and cleans up via trap.
- **Appropriate skip logic:** Docker tests gracefully skip rather than fail when Docker is unavailable.
- **No mocking needed:** As specified in test.md, all tests operate on real files and commands.
- **Test script is well-structured:** Numbered sections match test.md scenario numbers exactly, making traceability straightforward.

VERDICT: ADEQUATE
