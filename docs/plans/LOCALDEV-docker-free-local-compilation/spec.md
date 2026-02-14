LOCALDEV
Created: 2026-02-14 14:54

# Docker-Free Local Compilation Pipeline

**Goal references:** [PURERB](../../goals/PURERB-pure-ruby-runtime.md), [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

## Problem Statement

The main compilation scripts ([compile](../../compile) and [compile2](../../compile2)) use Docker for every step: running `ruby driver.rb`, invoking `gcc -m32`, and linking. This means every compile-run-test cycle pays Docker container startup overhead (~1-2s per invocation), and Docker must be installed and the `ruby-compiler-buildenv` image must be built before any development can happen.

Local compilation scripts ([compile_local](../../compile_local) and [compile2_local](../../compile2_local)) already exist but are disconnected from the build system — the Makefile, `run_rubyspec`, and all `make` targets still use the Docker-based `./compile` and `./compile2`. The `fetch-glibc32` target itself requires Docker to extract libraries from the container image.

## Root Cause

The Docker dependency was introduced because the compiler targets i386 and development machines are typically x86-64. Compiling and linking 32-bit binaries requires:

1. A 32-bit-capable assembler (GAS with `--32`) — **already available** on most x86-64 Linux hosts
2. A 32-bit-capable GCC (`gcc -m32 -c`) — **already available** on most x86-64 hosts with GCC
3. 32-bit libc and CRT objects for linking — **NOT typically installed** (requires `gcc-multilib` or `libc6-dev-i386` package, or the extracted Docker toolchain)

The current `fetch-glibc32` Makefile target bridges gap #3 by copying 32-bit libraries from inside the Docker image to `toolchain/32root/`. This works, but still requires Docker to bootstrap. The `compile_local` and `compile2_local` scripts then use these extracted libraries for linking.

The missing piece is: (a) a way to populate `toolchain/32root/` without Docker (using apt or direct download), and (b) making `./compile` and `./compile2` auto-detect local toolchain availability and prefer it over Docker.

## Prior Plans

No prior plans targeting this area were found in `docs/plans/archived/`.

## Infrastructure Cost

Low. The changes are confined to build scripts and the Makefile:
- Modify 2 existing files: [compile](../../compile), [compile2](../../compile2)
- Modify 1 Makefile
- Add 1 new script: `bin/setup-i386-toolchain`
- No compiler code changes. No library code changes. No test changes.

## Scope and Deliverables

### 1. `bin/setup-i386-toolchain` — Docker-free toolchain setup

Create a script that populates `toolchain/32root/` without requiring Docker. The script should:

- **Primary method**: Use `apt` to install `gcc-multilib` and `libc6-dev-i386`, then symlink or copy the system-provided 32-bit libraries into `toolchain/32root/`. On Debian/Ubuntu systems, `dpkg --add-architecture i386 && apt install libc6-dev-i386 gcc-multilib` provides everything needed. The script detects the installed GCC version (e.g., 11 on Ubuntu 22.04) and adjusts paths accordingly instead of hardcoding GCC 8 (as the current Docker image uses).
- **Fallback method**: If `apt` is unavailable or the user lacks root, download the necessary `.deb` packages from the Debian/Ubuntu archive and extract them with `dpkg-deb -x` (no root needed). The specific packages are: `libc6-dev-i386`, `libc6-i386`, `lib32gcc-s1` (or `lib32gcc1` on older systems), and the appropriate `libgcc-N-dev` (32-bit cross files).
- **Docker method**: Keep `make fetch-glibc32` as a third option for users who already have Docker.
- Output a validation summary showing which CRT objects and libraries were found.

### 2. Unify `compile` / `compile_local` into a single script

Modify [compile](../../compile) to:
- Check if `toolchain/32root/` exists and contains the required files (libc.so.6, crt1.o).
- If yes: use the local toolchain path (the logic currently in `compile_local`).
- If no: fall back to Docker (current behavior).
- Print which mode was selected ("local toolchain" vs "Docker") in the status output.

Apply the same unification to [compile2](../../compile2) / [compile2_local](../../compile2_local).

After unification, `compile_local` and `compile2_local` become redundant and can be deleted.

### 3. Makefile integration

- Add `setup-toolchain` target that calls `bin/setup-i386-toolchain`.
- Ensure all existing targets (`selftest`, `selftest-c`, `compiler`, etc.) continue to work unchanged — they already call `./compile` which will now auto-select the mode.
- Add a `local-check` target that verifies the toolchain is correctly set up.

### 4. GCC version flexibility

The current `compile_local` hardcodes GCC 8 paths (`gcc/x86_64-linux-gnu/8/32`). The unified script must detect the actual host GCC version. On Ubuntu 22.04 the GCC is version 11; on newer Ubuntu it's 12 or 13. The script should find the correct `crtbegin.o` / `crtend.o` by searching `/usr/lib/gcc/x86_64-linux-gnu/*/32/` or equivalent.

## Expected Payoff

- **Development iteration speed**: Eliminates Docker container startup overhead on every compilation. For `run_rubyspec` which compiles dozens of specs sequentially, this is substantial.
- **Reduced setup friction**: `bin/setup-i386-toolchain` + `make compiler` is a simpler onboarding path than Docker build + image management.
- **Foundation for PURERB**: The eventual Ruby assembler/linker (mentioned in README.md line 31-32) would remove GAS/LD entirely, making Docker even less relevant. This plan is the intermediate step — remove Docker from the *workflow*, before later removing GAS/LD from the *pipeline*.
- **Sandboxed dev environments**: AI development environments typically don't have Docker. Making the build work with just `apt` packages means the compiler can be developed in sandboxed Linux environments.

## Risks

- **Non-Debian systems**: The apt-based approach is Debian/Ubuntu-specific. Users on Fedora, Arch, etc. would need different packages. The script should detect the distro and either provide instructions or use the `.deb` extraction fallback.
- **GCC version fragility**: Different distros place 32-bit CRT objects in different locations. The script needs to search rather than hardcode.

## Acceptance Criteria

- [x] `bin/setup-i386-toolchain` exists and successfully populates `toolchain/32root/` on a Debian/Ubuntu x86-64 system without Docker.
- [x] `./compile driver.rb -I . -g` succeeds with the local toolchain (no Docker running) and produces a working `out/driver`.
- [x] `./compile2 driver.rb -I . -g` succeeds with the local toolchain and produces a working `out/driver2`.
- [x] `make selftest` passes using the unified `./compile` with local toolchain.
- [x] `make selftest-c` passes using the unified `./compile` and `./compile2` with local toolchain.
- [x] `./compile` falls back to Docker gracefully when `toolchain/32root/` is missing and Docker is available.
- [x] `compile_local` and `compile2_local` are deleted (their logic is merged into `compile` and `compile2`).
- [x] The unified `compile` script auto-detects the host GCC version rather than hardcoding GCC 8.
- [x] `run_rubyspec` works without modification (it calls `./compile` which now handles mode selection).

## Implementation Details

### Files to read/modify

- [compile](../../compile) (33 lines) — Currently a pure-Docker script. The `dr()` helper on line 11-13 wraps every command in `docker run`. Three `dr()` calls: line 17 (ruby driver.rb), line 18 (gcc -c tgc.c), line 24 (gcc link). Must be restructured to conditionally use local toolchain or Docker.
- [compile2](../../compile2) (33 lines) — Near-identical to `compile` but invokes `out/driver` (the compiled compiler) instead of `ruby driver.rb` on line 17 and appends `2` to output names (lines 16, 17, 24). Same restructuring needed.
- [compile_local](../../compile_local) (72 lines) — Contains the local toolchain logic to merge into `compile`. Key elements:
  - GCC version path resolution: line 15 (`gcc32` variable) — currently hardcoded to GCC 8
  - Toolchain root detection: line 11 (`GLIBC32_ROOT` env var with fallback)
  - Required file validation: line 23 (checks for `libc.so.6` and `crt1.o`)
  - Link flags construction: lines 45-66 (nostdlib, explicit CRT objects, library paths)
  - tgc.o caching: lines 37-43 (only recompiles if missing)
- [compile2_local](../../compile2_local) (72 lines) — Identical to `compile_local` except: line 33 uses `out/driver` instead of `ruby driver.rb`, and output names have `2` suffix. Will be deleted after merge.
- [Makefile](../../Makefile) (105 lines) — Targets to modify:
  - `fetch-glibc32` (lines 74-82): Keep as-is, add `setup-toolchain` and `local-check` targets
  - `selftest-c2` (line 60-63) and `hello` (line 25-27): These use `${DR}` (Docker) directly — consider leaving as-is (these are minor/legacy targets)
- [.gitignore](../../.gitignore) — line 4 has `bin/*` which would ignore `bin/setup-i386-toolchain`. Need to add an exception: `!bin/setup-i386-toolchain`.
- [run_rubyspec](../../run_rubyspec) — line 134 calls `./compile` — no changes needed (will automatically benefit from the unified script).

### Key variables and paths in compile_local to preserve

The local toolchain logic uses these directory layout assumptions (matching the Docker image's Debian Buster layout):

| Variable       | Path under `toolchain/32root/`                    | Contains                        |
|----------------|---------------------------------------------------|---------------------------------|
| `lib32`        | `lib/i386-linux-gnu/`                             | `libc.so.6`, `ld-linux.so.2`, `libgcc_s.so.1` |
| `usr32`        | `usr/lib32/`                                      | `crt1.o`, `crti.o`, `crtn.o`, `libc_nonshared.a` |
| `usr_i386`     | `usr/lib/i386-linux-gnu/`                         | Additional i386 libs            |
| `gcc32`        | `usr/lib/gcc/x86_64-linux-gnu/<VER>/32/`          | `crtbegin.o`, `crtend.o`       |
| `dynamic_linker` | `lib/i386-linux-gnu/ld-linux.so.2`              | Dynamic linker                  |

On host systems with `gcc-multilib` installed, the same files live under system paths:
- `/usr/lib32/` or `/usr/lib/i386-linux-gnu/` — CRT objects
- `/lib/i386-linux-gnu/` or `/lib32/` — shared libs
- `/usr/lib/gcc/x86_64-linux-gnu/<VER>/32/` — GCC CRT objects

The `bin/setup-i386-toolchain` script must map from system paths to the `toolchain/32root/` layout that `compile_local` expects.

### Design for the unified compile script

The unified `compile` script should:

1. Keep the existing `dr()` function for Docker mode.
2. Add a new function (e.g., `local_toolchain_available?`) that checks:
   - `toolchain/32root/lib/i386-linux-gnu/libc.so.6` exists
   - `toolchain/32root/usr/lib32/crt1.o` exists
   - A `crtbegin.o` exists somewhere under `toolchain/32root/usr/lib/gcc/`
3. Add a `find_gcc_version()` function that globs for `toolchain/32root/usr/lib/gcc/x86_64-linux-gnu/*/32/crtbegin.o` and returns the first match's version directory.
4. Support `COMPILE_MODE=docker` or `COMPILE_MODE=local` env var to force a specific mode.
5. Merge the local toolchain linking logic from `compile_local` (lines 45-72) into `compile` inside a conditional branch.

The key difference between `compile` and `compile2` is only the compilation step (line 17): `ruby driver.rb` vs `out/driver`. The linking step is identical. Both should share the same local-toolchain linking logic.

### Design for bin/setup-i386-toolchain

The script should be a bash script that:

1. Checks if `toolchain/32root/` is already populated and valid → skip if so.
2. Detects the distro (check `/etc/os-release` for `ID=debian`, `ID=ubuntu`, etc.).
3. **Method 1 (apt, needs root)**: Check if `libc6-dev-i386` and `gcc-multilib` packages are installed. If not, offer to install them. Then symlink/copy from system paths into `toolchain/32root/`.
4. **Method 2 (deb extraction, no root)**: Download `.deb` packages from the Ubuntu/Debian archive and extract with `dpkg-deb -x`.
5. Detect the system GCC version by inspecting `/usr/lib/gcc/x86_64-linux-gnu/*/` or `gcc -dumpversion`.
6. Validate the result by checking all required files exist.

### Edge cases

- **tgc.o caching**: `compile_local` only recompiles `tgc.c` if `out/tgc.o` doesn't exist (line 37). The Docker-based `compile` recompiles it every time (line 18). The unified script should follow the local behavior (cache `tgc.o`), since recompiling a C file unnecessarily wastes time.
- **`/tmp` volume mount**: The Docker `dr()` in `compile` (line 13) mounts `-v /tmp:/tmp` but `compile2` (line 13) does not. The unified script should not need `/tmp` mounts in local mode, but Docker fallback should preserve existing behavior.
- **`2>&1` redirect**: `compile2` line 17 redirects stderr to stdout (`2>&1 >out/...`). `compile` line 17 does not. The unified script must preserve this difference.
- **`.gitignore` has `bin/*`**: This will ignore the new `bin/setup-i386-toolchain` script. Must add `!bin/setup-i386-toolchain` exception.

## Execution Steps

1. [ ] Create `bin/setup-i386-toolchain` bash script — Create the directory `bin/` and the script. Implement: (a) detect distro via `/etc/os-release`, (b) check if `gcc-multilib` and `libc6-dev-i386` are installed via `dpkg -s`, (c) detect GCC version by globbing `/usr/lib/gcc/x86_64-linux-gnu/*/`, (d) populate `toolchain/32root/` by symlinking from system paths, (e) validate required files (`crt1.o`, `crti.o`, `crtn.o`, `crtbegin.o`, `crtend.o`, `libc.so.6`, `ld-linux.so.2`, `libgcc_s.so.1`, `libc_nonshared.a`), (f) print validation summary. Make it executable (`chmod +x`).

2. [ ] Unify `compile` with `compile_local` — Rewrite [compile](../../compile) to: (a) keep the existing `dr()` Docker helper, (b) add a `local_toolchain_available?` check function, (c) add a `find_gcc32_dir()` function that globs `toolchain/32root/usr/lib/gcc/x86_64-linux-gnu/*/32/crtbegin.o`, (d) add a `run_local()` path that uses the linking logic from [compile_local](../../compile_local) lines 11-72, (e) support `COMPILE_MODE` env var override, (f) print mode selection ("Using local toolchain" vs "Using Docker"). Preserve the existing Docker path as fallback.

3. [ ] Unify `compile2` with `compile2_local` — Apply the same pattern to [compile2](../../compile2): same structure as step 2 but with the `out/driver` invocation (instead of `ruby driver.rb`) and `2` output suffix. The differences from `compile` are: line 17 uses `#{dir}/out/driver` and line 13 omits the `-v /tmp:/tmp` Docker mount. Preserve these differences.

4. [ ] Delete `compile_local` and `compile2_local` — Remove [compile_local](../../compile_local) and [compile2_local](../../compile2_local) since their logic is now merged into `compile` and `compile2`.

5. [ ] Update `.gitignore` — Add `!bin/setup-i386-toolchain` exception after the `bin/*` line in [.gitignore](../../.gitignore):4 so the new script is tracked by git.

6. [ ] Add Makefile targets — Add to [Makefile](../../Makefile): (a) `setup-toolchain` phony target that runs `bin/setup-i386-toolchain`, (b) `local-check` phony target that checks for required files in `toolchain/32root/` and prints status. Add both to `.PHONY` declarations.

7. [ ] Test: Run `bin/setup-i386-toolchain` — Execute the setup script and verify it populates `toolchain/32root/` correctly. Check that all required CRT objects and libraries are present.

8. [ ] Test: `./compile driver.rb -I . -g` with local toolchain — Verify the unified `compile` selects local mode and produces a working `out/driver`. Check it prints "Using local toolchain" or similar.

9. [ ] Test: `make selftest` — Run `make selftest` to verify end-to-end compilation and execution works with the unified `compile`.

10. [ ] Test: `make selftest-c` — Run `make selftest-c` to verify `compile2` also works correctly via the unified script.

11. [ ] Test: Docker fallback — Temporarily rename `toolchain/32root/` and verify `./compile` falls back to Docker mode (or prints a clear error if Docker is unavailable). Restore `toolchain/32root/` afterward.

12. [ ] Test: `run_rubyspec` — Run `./run_rubyspec spec/` (a quick subset) to verify the rubyspec runner works without modification through the unified `compile`.

---
*Status: APPROVED*