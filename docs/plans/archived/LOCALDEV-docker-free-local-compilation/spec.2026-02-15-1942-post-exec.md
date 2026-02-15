LOCALDEV
Created: 2026-02-14 14:54

# Docker-Free Local Compilation Pipeline

> **User direction (2026-02-15 19:23):** Still uses docker all over the place. Whatever you did has been lost, possibly to bugs in improve. Redo.

> **User direction (2026-02-14 15:27):** Focus should be on the *simplest possible approach*.

> **User direction (2026-02-15 19:23):** Still uses Docker all over the place. Previous execution's changes were lost. Redo.

**Goal references:** [PURERB](../../goals/PURERB-pure-ruby-runtime.md), [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

## Problem Statement

The compilation scripts ([compile](../../compile) and [compile2](../../compile2)) use Docker for every step. A local compilation script ([compile_local](../../compile_local)) exists and works but is disconnected from the build system — the Makefile, `run_rubyspec`, and all `make` targets still use the Docker-based `./compile` and `./compile2`.

Two previous execution attempts failed — changes were lost. The `compile` and `compile2` scripts are unchanged and still pure Docker. The `compile_local` script still exists as a separate file. The local toolchain logic was never merged in. The Makefile still uses `${DR}` (Docker) in several targets. Nothing from the previous executions survived.

## Approach

The simplest possible approach: merge the existing `compile_local` logic into `compile` (and equivalent logic into `compile2`). If `toolchain/32root/` exists, use local toolchain. Otherwise fall back to Docker. Fix the hardcoded GCC 8 path to auto-detect. That's it.

Additionally, the Makefile has targets that directly use `${DR}` (Docker) — `selftest-c2`, `hello`, `valgrind`, `fetch-glibc32`. These also need attention to ensure `make selftest` and `make selftest-c` work without Docker.

No new setup scripts. No distro detection. No deb extraction. The existing `make fetch-glibc32` or manual package installation (`apt install gcc-multilib libc6-dev-i386`) + existing `fetch-glibc32` already populate the toolchain directory. This plan only unifies the compile scripts.

## Infrastructure Cost

Low. Modify 2 existing files, delete 1 file, minor Makefile touch-ups.

## Scope and Deliverables

### 1. Unify `compile` with `compile_local`

Modify [compile](../../compile) to:
- Check if `toolchain/32root/` exists and contains the required files.
- If yes: use the local toolchain path (the logic currently in `compile_local`).
- If no: fall back to Docker (current behavior).
- Auto-detect the host GCC version by globbing for `crtbegin.o` instead of hardcoding GCC 8.

Apply the same to [compile2](../../compile2) (there is no `compile2_local` — port the logic from `compile_local` with the appropriate `out/driver` invocation).

After unification, delete `compile_local`.

### 2. Makefile cleanup

- Ensure `make selftest` and `make selftest-c` work without Docker when the local toolchain is present (they call `./compile` and `./compile2`, so unifying the compile scripts should be sufficient).
- Review other Makefile targets that use `${DR}` directly (`selftest-c2`, `hello`, `valgrind`) and ensure they don't break the local compilation path.
- Add a `setup-toolchain` target that runs `apt install gcc-multilib libc6-dev-i386` then `make fetch-glibc32` (or equivalent), as a convenience.

## Acceptance Criteria

1. `./compile driver.rb -I . -g` succeeds with the local toolchain (no Docker running) and produces a working `out/driver`.
2. `./compile2 driver.rb -I . -g` succeeds with the local toolchain and produces a working `out/driver2`.
3. `make selftest` passes using the unified `./compile` with local toolchain — no Docker involved.
4. `make selftest-c` passes using the unified `./compile` and `./compile2` with local toolchain — no Docker involved.
5. `./compile` falls back to Docker gracefully when `toolchain/32root/` is missing and Docker is available.
6. `compile_local` is deleted.
7. The unified `compile` script auto-detects the host GCC version rather than hardcoding GCC 8.
8. `run_rubyspec` works without modification (it calls `./compile` which will now use local toolchain).

## Implementation Details

### Files to read/modify

- [compile](../../compile) (33 lines) — Currently a pure-Docker script. Must be restructured to conditionally use local toolchain or Docker.
- [compile2](../../compile2) (33 lines) — Same restructuring.
- [compile_local](../../compile_local) (72 lines) — Contains the local toolchain logic to merge into `compile`. Key elements: GCC version path (line 15, hardcoded to GCC 8), toolchain root detection (line 11), required file validation (line 23), link flags (lines 45-66), tgc.o caching (lines 37-43). Will be deleted after merge.
- [Makefile](../../Makefile) — Add `setup-toolchain` convenience target. Review `${DR}` usage in other targets.

Note: `compile2_local` does not exist. The `compile2` unification must port logic from `compile_local` directly.

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

2. [ ] Unify `compile2` — Port the local toolchain logic into [compile2](../../compile2) with `out/driver` invocation and `2` output suffix.

3. [ ] Delete `compile_local`.

4. [ ] Add `setup-toolchain` Makefile target — A convenience target that documents/runs the package install + `fetch-glibc32` steps.

5. [ ] Test: `make selftest` — Verify end-to-end compilation works with the unified `compile`, no Docker involved.

6. [ ] Test: `make selftest-c` — Verify `compile2` works correctly, no Docker involved.

7. [ ] Test: Docker fallback — Temporarily rename `toolchain/32root/` and verify `./compile` falls back to Docker mode. Restore afterward.

---
*Status: APPROVED (re-exec — previous execution changes were lost)*
