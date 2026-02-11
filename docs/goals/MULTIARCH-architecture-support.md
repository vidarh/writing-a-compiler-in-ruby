MULTIARCH

# Multi-Architecture Support

Add x86-64 code generation as a second target architecture, using this as the forcing function to cleanly separate architecture-specific code from architecture-independent compiler logic, creating a path to supporting additional architectures in the future.

## Vision

The compiler can target both x86 (32-bit) and x86-64 (64-bit) from the same source. Architecture-specific code (register names, calling conventions, pointer sizes, instruction encoding) is isolated in backend modules, while the parser, AST, transformer, and high-level compilation logic remain architecture-independent. Adding a new architecture backend requires implementing a well-defined interface without touching the frontend. x86-64 support also removes the Docker/i386 build environment requirement for development on modern 64-bit systems.

## Why This Matters

The compiler currently targets only 32-bit x86, which is increasingly difficult to develop for (requires Docker containers with i386 toolchain, multilib GCC). Moving to x86-64 as the primary target would simplify the development environment and produce binaries that run natively on modern systems. More importantly, the process of adding a second architecture forces a clean separation of concerns that improves the overall codebase quality. The compiler currently has architecture assumptions scattered throughout (PTR_SIZE = 4, specific register names, calling conventions) -- refactoring these into a backend abstraction would make the code more maintainable regardless of how many architectures are supported.

## Sources

Where this goal was discovered:
- README.md (lines 26-27): "Clean up separation of concerns and add x86-64 support and use that as a path to proper multi-arch support."
- docs/ARCHITECTURE.md (lines 165-168): Documents "x86 32-bit Target" with 4-byte pointers, x86 calling conventions, and notes that "All development done in Docker containers for consistency" -- highlighting the friction of 32-bit-only support
- docs/ARCHITECTURE.md (lines 79-81): Assembly generation in emitter.rb "Generates x86 32-bit assembly code" with architecture-specific register allocation
- README.md (line 29): "General cleanup. The code has gotten messy. Decompose into simpler components. Make things simpler. Deduplicate." -- the cleanup needed is partly about separating arch-specific from arch-independent code

## Related Goals

- [SELFHOST](SELFHOST-clean-bootstrap.md): A clean bootstrap must work on the new architecture; x86-64 bootstrap would be a major milestone
- [PURERB](PURERB-pure-ruby-runtime.md): A built-in assembler would need to support multiple instruction encodings; the architecture abstraction enables this
- [CODEGEN](CODEGEN-output-code-quality.md): x86-64 has more registers and different calling conventions, offering optimization opportunities not available on 32-bit

## Potential Plans

Ideas for incremental plans that would advance this goal:
- Audit all architecture-specific constants and patterns in the compiler (PTR_SIZE, register names, calling conventions, instruction formats) and document them as the "backend interface"
- Extract the current x86-32 code generation into a backend module behind an abstraction layer
- Implement a minimal x86-64 backend that can compile and run a "hello world" program
- Add a build flag to select target architecture, with x86-32 remaining the default until x86-64 passes selftest

---
*Status: GOAL*
