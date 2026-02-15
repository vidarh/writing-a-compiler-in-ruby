# Test Specification: LOCALDEV — Docker-Free Local Compilation

## Test Suite Location

All tests go in a single validation script:
`test/test_localdev.sh`

This plan modifies build scripts (bash/Ruby) and the Makefile — not
compiler code or Ruby libraries. The deliverables are shell scripts and
Makefile targets, so the appropriate test framework is a shell-based
validation script (matching the pattern used by PLANGUIDE's
`tools/check_planguide.sh`).

No `spec/` mspec tests are needed — there is no Ruby language behavior
to test.

## Design Requirements

### No abstractions or mocking interfaces needed

The deliverables are shell scripts (`bin/setup-i386-toolchain`,
`compile`, `compile2`) and Makefile targets. These operate on the
filesystem (checking for files, running gcc, running ruby). They are
tested by running them and checking results.

### Testability constraints

The unified `compile` and `compile2` scripts must support the
`COMPILE_MODE` environment variable as specified in the plan:
- `COMPILE_MODE=local` — force local toolchain (fail if unavailable)
- `COMPILE_MODE=docker` — force Docker
- unset — auto-detect (prefer local if available)

This env var is the primary testability mechanism. It allows the test
script to force specific code paths without needing to manipulate
`toolchain/32root/` or Docker availability.

The `compile` and `compile2` scripts must also print which mode was
selected to stdout/stderr (e.g., "Using local toolchain" or "Using
Docker"). The test script verifies this output to confirm the correct
code path was taken.

### No refactoring of existing code needed

The plan creates new scripts and modifies existing ones. No existing
abstractions need to be changed for testability.

## Required Test Coverage

All scenarios below are verified by `test/test_localdev.sh`. Each
check prints a PASS/FAIL line. The script exits non-zero if any check
fails.

### 1. File existence and permissions

- `bin/setup-i386-toolchain` exists and is executable
- `compile` exists and is executable
- `compile2` exists and is executable
- `compile_local` does NOT exist (deleted after merge)
- `compile2_local` does NOT exist (deleted after merge)

### 2. `.gitignore` exception

- `.gitignore` contains a line matching `!bin/setup-i386-toolchain`
  (so the script is tracked by git despite the `bin/*` ignore rule)
- `git ls-files bin/setup-i386-toolchain` returns the file (git
  actually tracks it, not just that the gitignore line exists)

### 3. Makefile targets

- `Makefile` contains a target named `setup-toolchain`
- `Makefile` contains a target named `local-check`
- Both targets appear in a `.PHONY` declaration
- `make -n setup-toolchain` succeeds (dry-run, validates syntax)
- `make -n local-check` succeeds (dry-run, validates syntax)

### 4. `bin/setup-i386-toolchain` — toolchain population

- Running `bin/setup-i386-toolchain` exits 0 on a Debian/Ubuntu
  x86-64 system with `gcc-multilib` and `libc6-dev-i386` installed
- After running, `toolchain/32root/` is populated
- Required files exist after setup:
  - `toolchain/32root/lib/i386-linux-gnu/libc.so.6`
  - `toolchain/32root/lib/i386-linux-gnu/ld-linux.so.2`
  - `toolchain/32root/lib/i386-linux-gnu/libgcc_s.so.1`
  - `toolchain/32root/usr/lib32/crt1.o`
  - `toolchain/32root/usr/lib32/crti.o`
  - `toolchain/32root/usr/lib32/crtn.o`
  - `toolchain/32root/usr/lib32/libc_nonshared.a`
  - At least one `toolchain/32root/usr/lib/gcc/x86_64-linux-gnu/*/32/crtbegin.o`
  - At least one `toolchain/32root/usr/lib/gcc/x86_64-linux-gnu/*/32/crtend.o`
- The script prints a validation summary listing found/missing files
- Running the script a second time (idempotent) also exits 0 and does
  not corrupt the existing toolchain directory

### 5. `bin/setup-i386-toolchain` — error handling

- On a system where `gcc-multilib` is NOT installed and `dpkg-deb` is
  not available, the script exits non-zero with a clear error message
  (not a silent failure or cryptic shell error). **Note:** This
  scenario may not be directly testable in the execution environment
  if `gcc-multilib` is already installed. The test script should check
  that the script contains validation logic (grep for the required
  file checks) rather than attempting to simulate a missing package.
- If `toolchain/32root/` already exists and is valid, the script
  detects this and skips re-population (prints a message indicating
  the toolchain is already set up)

### 6. GCC version detection

- The `bin/setup-i386-toolchain` script does NOT hardcode GCC version
  "8" anywhere. Grep the script for `/8/` or `gcc-8` — no matches
  should appear.
- The script detects the actual GCC version by globbing or querying
  `gcc -dumpversion`. The test verifies the detected version matches
  `gcc -dumpversion | cut -d. -f1` on the host.
- `crtbegin.o` in `toolchain/32root/` is under a directory matching
  the host GCC version (e.g., `*/11/32/crtbegin.o` on GCC 11), not
  under `*/8/32/`.

### 7. Unified `compile` — local mode

- `COMPILE_MODE=local ./compile test/hello.rb -I.` (or a minimal
  `.rb` file) succeeds when `toolchain/32root/` is populated. If
  `test/hello.rb` doesn't exist, create a trivial one-liner in a temp
  file.
- The output contains "local" (case-insensitive) indicating local
  toolchain mode was selected
- The compiled binary exists in `out/`
- The compiled binary runs and produces expected output

### 8. Unified `compile` — Docker fallback

- With `toolchain/32root/` renamed/absent AND Docker available:
  `COMPILE_MODE=docker ./compile test/hello.rb -I.` succeeds
- The output contains "docker" (case-insensitive) indicating Docker
  mode was selected
- **If Docker is NOT available in the test environment**: skip this
  test (print SKIP, do not count as failure). Check for Docker with
  `command -v docker >/dev/null 2>&1`.

### 9. Unified `compile` — auto-detect mode

- With `toolchain/32root/` populated and `COMPILE_MODE` unset:
  `./compile test/hello.rb -I.` succeeds and selects local mode
- The output contains "local" (case-insensitive)

### 10. Unified `compile` — forced local without toolchain

- With `toolchain/32root/` temporarily renamed and
  `COMPILE_MODE=local`: `./compile test/hello.rb -I.` exits non-zero
  with a clear error message about missing toolchain
- The error message mentions `toolchain` or `32root` or
  `setup-i386-toolchain`

### 11. Unified `compile2` — local mode

- `COMPILE_MODE=local ./compile2 driver.rb -I . -g` succeeds when
  `toolchain/32root/` is populated AND `out/driver` exists (compile2
  requires the stage-1 compiler)
- The output contains "local" (case-insensitive)
- `out/driver2` exists after compilation
- **Prerequisite**: `out/driver` must exist. If not, run
  `./compile driver.rb -I . -g` first.

### 12. Unified `compile2` — preserves `2>&1` redirect

- `compile2` still redirects stderr to stdout on the compilation step
  (the `2>&1 >out/...` pattern from the original `compile2`). Verify
  by grepping the script for `2>&1`.

### 13. Unified `compile` — tgc.o caching

- Delete `out/tgc.o` if it exists, then run `./compile` on a test
  file. Verify `out/tgc.o` is created.
- Run `./compile` again on a different test file. Verify `out/tgc.o`
  is NOT recompiled (check mtime is unchanged). This validates the
  caching behavior from `compile_local`.

### 14. `make selftest` integration

- `make selftest` passes end-to-end with the unified `compile` using
  local toolchain
- This is the critical integration test: compile `test/selftest.rb`
  with the MRI-driven compiler, then run the resulting binary

### 15. `make selftest-c` integration

- `make selftest-c` passes end-to-end with the unified `compile` and
  `compile2` using local toolchain
- This validates the self-compilation path: compile with `compile`,
  then use the result (`out/driver`) via `compile2` to compile the
  selftest again

### 16. `run_rubyspec` compatibility

- `./run_rubyspec spec/bug_ternary_expression_spec.rb` (or any
  single known-working spec) succeeds without modification to
  `run_rubyspec`
- `run_rubyspec` calls `./compile` which now auto-selects local mode
  — this must work transparently

### 17. `COMPILE_MODE=docker` passthrough in `compile2`

- The Docker volume mount difference is preserved: `compile` mounts
  `-v /tmp:/tmp` in Docker mode but `compile2` does not. Verify by
  grepping the scripts. `compile` must contain `/tmp:/tmp` in its
  Docker path; `compile2` must NOT.

### 18. No compiler code changes

- `git diff --name-only` (against the branch point) does NOT include
  any `.rb` files in the root directory (compiler source) or
  `lib/core/` (runtime libraries). Only build scripts (`compile`,
  `compile2`), `Makefile`, `.gitignore`, `bin/setup-i386-toolchain`,
  and `docs/plans/` files should appear.

## Mocking Strategy

**No mocking is needed.** All tests operate on real files and real
commands. The `COMPILE_MODE` environment variable provides the
test-control mechanism for switching between code paths.

For tests that require `toolchain/32root/` to be absent (scenarios 10,
8), temporarily rename the directory:

```bash
mv toolchain/32root toolchain/32root.bak
# ... run test ...
mv toolchain/32root.bak toolchain/32root
```

Use a trap to ensure restoration on failure:

```bash
cleanup() { [ -d toolchain/32root.bak ] && mv toolchain/32root.bak toolchain/32root; }
trap cleanup EXIT
```

No network access is needed. No Docker is required for the primary
test path (local toolchain tests). Docker-specific tests (scenario 8)
are skipped if Docker is unavailable.

## Invocation

```bash
bash test/test_localdev.sh
```

Exit code 0 on full success, non-zero on any failure. Each check
prints a one-line result:

```
PASS: bin/setup-i386-toolchain exists and is executable
PASS: compile_local deleted
FAIL: toolchain/32root/usr/lib32/crt1.o missing
...
X passed, Y failed, Z skipped
```

For the integration tests (scenarios 14-16), the test script runs
`make selftest`, `make selftest-c`, and `./run_rubyspec` as
subcommands and checks their exit codes.

## Known Pitfalls

1. **Do NOT run `make selftest` or `make selftest-c` without a
   populated `toolchain/32root/`.** The unified `compile` will try
   Docker fallback if the toolchain is missing, and Docker may not be
   available. Run `bin/setup-i386-toolchain` first.

2. **The `toolchain/` directory is in `.gitignore`.** The test script
   must not expect `toolchain/32root/` to exist before
   `bin/setup-i386-toolchain` runs. The test should run the setup
   script as its first action.

3. **`out/tgc.o` caching test is order-dependent.** The mtime check
   (scenario 13) requires running two compilations in sequence. The
   test must `sleep 1` between compilations to ensure filesystem
   timestamps differ if recompilation occurs.

4. **The Docker fallback test (scenario 8) requires Docker.** If
   Docker is not installed or the `ruby-compiler-buildenv` image is
   not built, this test must be skipped — not failed. Use
   `command -v docker` and `docker image inspect ruby-compiler-buildenv`
   to check availability.

5. **`compile2` requires `out/driver` to exist.** Scenario 11 depends
   on having a working stage-1 compiler. The test must ensure
   `out/driver` exists (by running `./compile driver.rb -I . -g`
   first) before testing `compile2`.

6. **Do NOT hardcode GCC version in test assertions.** The test must
   dynamically determine the host GCC version (via `gcc -dumpversion`)
   and use it in path checks. Different CI environments will have
   different GCC versions.

7. **The `compile` and `compile2` scripts are Ruby scripts, not
   bash.** They start with `#!/usr/bin/ruby`. The test script should
   not assume they are bash scripts when grepping for patterns.

8. **Restore `toolchain/32root/` after rename tests.** Scenarios 8
   and 10 temporarily rename the directory. A trap handler must ensure
   restoration even if the test crashes. Failure to restore will break
   all subsequent tests.

9. **Do NOT modify `run_rubyspec`.** The plan states `run_rubyspec`
   needs no changes. Scenario 16 verifies this — if it fails, the bug
   is in the unified `compile`, not in `run_rubyspec`.

10. **The `.gitignore` has `bin/*` on line 4.** The exception
    `!bin/setup-i386-toolchain` must come AFTER the `bin/*` line.
    Verify ordering, not just presence.

11. **`make selftest-c` is slow.** It compiles the compiler twice
    (once with MRI, once with itself). Budget accordingly in CI. Do
    not add a timeout shorter than 10 minutes.

12. **The test script itself should be idempotent.** Running it
    multiple times should produce the same results. It must clean up
    any temp files it creates (temp `.rb` files for compilation
    tests).

13. **Do NOT test `bin/setup-i386-toolchain` with `--dry-run` or
    simulation flags.** The script should be run for real. The
    toolchain directory it populates is needed by all subsequent
    tests. If the test environment lacks `apt` and `dpkg-deb`, the
    toolchain setup test should be skipped — but all file-existence
    and script-content tests should still run.
