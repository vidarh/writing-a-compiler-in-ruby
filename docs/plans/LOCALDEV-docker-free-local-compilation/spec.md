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

1. `bin/setup-i386-toolchain` exists and successfully populates `toolchain/32root/` on a Debian/Ubuntu x86-64 system without Docker.
2. `./compile driver.rb -I . -g` succeeds with the local toolchain (no Docker running) and produces a working `out/driver`.
3. `./compile2 driver.rb -I . -g` succeeds with the local toolchain and produces a working `out/driver2`.
4. `make selftest` passes using the unified `./compile` with local toolchain.
5. `make selftest-c` passes using the unified `./compile` and `./compile2` with local toolchain.
6. `./compile` falls back to Docker gracefully when `toolchain/32root/` is missing and Docker is available.
7. `compile_local` and `compile2_local` are deleted (their logic is merged into `compile` and `compile2`).
8. The unified `compile` script auto-detects the host GCC version rather than hardcoding GCC 8.
9. `run_rubyspec` works without modification (it calls `./compile` which now handles mode selection).

---
*Status: PROPOSED*
