LOCALDEV
Created: 2026-02-14 14:54

# Docker-Free Local Compilation Pipeline

> **User direction (2026-02-14 15:27):** Restarting after crash. Focus should be on the *simplest possible approach

**Goal references:** [PURERB](../../goals/PURERB-pure-ruby-runtime.md), [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

## Problem Statement

The main compilation scripts ([compile](../../compile) and [compile2](../../compile2)) use Docker for every step. Local compilation scripts ([compile_local](../../compile_local) and [compile2_local](../../compile2_local)) already exist and work but are disconnected from the build system — the Makefile, `run_rubyspec`, and all `make` targets still use the Docker-based `./compile` and `./compile2`.

## Approach

The simplest possible approach: merge the existing `compile_local` logic into `compile` (and `compile2_local` into `compile2`). If `toolchain/32root/` exists, use local toolchain. Otherwise fall back to Docker. Fix the hardcoded GCC 8 path to auto-detect. That's it.

No new setup scripts. No distro detection. No deb extraction. The existing `make fetch-glibc32` or manual package installation (`apt install gcc-multilib libc6-dev-i386`) + existing `fetch-glibc32` already populate the toolchain directory. This plan only unifies the compile scripts.

## Infrastructure Cost

Low. Modify 2 existing files, delete 2 files, minor Makefile/gitignore touch-ups.

## Scope and Deliverables

### 1. Unify `compile` with `compile_local`

Modify [compile](../../compile) to:
- Check if `toolchain/32root/` exists and contains the required files.
- If yes: use the local toolchain path (the logic currently in `compile_local`).
- If no: fall back to Docker (current behavior).
- Auto-detect the host GCC version by globbing for `crtbegin.o` instead of hardcoding GCC 8.

Apply the same to [compile2](../../compile2) / [compile2_local](../../compile2_local).

After unification, delete `compile_local` and `compile2_local`.

### 2. Makefile integration

- Ensure all existing targets continue to work unchanged — they already call `./compile`.
- Add a `setup-toolchain` target that runs `apt install gcc-multilib libc6-dev-i386` then `make fetch-glibc32` (or equivalent), as a convenience.

## Acceptance Criteria

1. `./compile driver.rb -I . -g` succeeds with the local toolchain (no Docker running) and produces a working `out/driver`.
2. `./compile2 driver.rb -I . -g` succeeds with the local toolchain and produces a working `out/driver2`.
3. `make selftest` passes using the unified `./compile` with local toolchain.
4. `make selftest-c` passes using the unified `./compile` and `./compile2` with local toolchain.
5. `./compile` falls back to Docker gracefully when `toolchain/32root/` is missing and Docker is available.
6. `compile_local` and `compile2_local` are deleted.
7. The unified `compile` script auto-detects the host GCC version rather than hardcoding GCC 8.
8. `run_rubyspec` works without modification.

## Implementation Details

### Files to read/modify

- [compile](../../compile) (33 lines) — Currently a pure-Docker script. Must be restructured to conditionally use local toolchain or Docker.
- [compile2](../../compile2) (33 lines) — Same restructuring.
- [compile_local](../../compile_local) (72 lines) — Contains the local toolchain logic to merge into `compile`. Key elements: GCC version path (line 15, hardcoded to GCC 8), toolchain root detection (line 11), required file validation (line 23), link flags (lines 45-66), tgc.o caching (lines 37-43).
- [compile2_local](../../compile2_local) (72 lines) — Same as `compile_local` but uses `out/driver` instead of `ruby driver.rb`. Will be deleted after merge.
- [Makefile](../../Makefile) — Add `setup-toolchain` convenience target.

### Design for the unified compile script

The unified `compile` script should:

1. Keep the existing `dr()` function for Docker mode.
2. Add a check: does `toolchain/32root/` contain `libc.so.6` and `crt1.o`?
3. Auto-detect GCC version by globbing `toolchain/32root/usr/lib/gcc/x86_64-linux-gnu/*/32/crtbegin.o`.
4. If local toolchain is available, use the linking logic from `compile_local` (lines 45-72).
5. If not, fall back to Docker via `dr()`.

The key difference between `compile` and `compile2` is the compilation step: `ruby driver.rb` vs `out/driver`. The linking step is identical.

### Edge cases to preserve

- **tgc.o caching**: The unified script should only recompile `tgc.c` if `out/tgc.o` doesn't exist (matching `compile_local` behavior).
- **`/tmp` volume mount**: Docker `dr()` in `compile` mounts `-v /tmp:/tmp` but `compile2` does not. Preserve this in Docker fallback.
- **`2>&1` redirect**: `compile2` redirects stderr to stdout on line 17. Preserve this difference.

## Execution Steps

1. [ ] Unify `compile` with `compile_local` — Merge the local toolchain logic from [compile_local](../../compile_local) into [compile](../../compile). Add local toolchain detection, GCC version auto-detection via glob, and Docker fallback. Keep the script simple.

2. [ ] Unify `compile2` with `compile2_local` — Same pattern as step 1, but with `out/driver` invocation and `2` output suffix.

3. [ ] Delete `compile_local` and `compile2_local`.

4. [ ] Add `setup-toolchain` Makefile target — A convenience target that documents/runs the package install + `fetch-glibc32` steps.

5. [ ] Test: `make selftest` — Verify end-to-end compilation works with the unified `compile`.

6. [ ] Test: `make selftest-c` — Verify `compile2` works correctly.

7. [ ] Test: Docker fallback — Temporarily rename `toolchain/32root/` and verify `./compile` falls back to Docker mode. Restore afterward.

---
*Status: APPROVED*
