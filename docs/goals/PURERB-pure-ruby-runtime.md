PURERB

# Pure Ruby Runtime

Eliminate all non-Ruby dependencies from the compiled runtime, replacing the C garbage collector with a Ruby implementation and removing the dependency on GCC's assembler and linker by building in a native assembler and ELF linker.

## Vision

A compiled Ruby program is a standalone native binary produced entirely by Ruby code. The garbage collector is written in Ruby (compiled to native code by the compiler itself). The assembler and linker are Ruby programs that emit ELF binaries directly, removing the dependency on GAS and LD. Optionally, libc is replaced with direct syscalls, making the output truly self-contained. The entire toolchain -- from Ruby source to running binary -- is implemented in Ruby.

## Why This Matters

Eliminating external dependencies is the natural endpoint of a self-hosting compiler. The C garbage collector (tgc.c) is currently the only statically-linked C component; replacing it would mean the compiler's output is 100% generated from Ruby. A built-in assembler/linker removes the GCC dependency from the compilation pipeline, making the compiler portable to any system where its own binary can run. This also enables future JIT compilation (generating and linking code at runtime) and makes the project a more compelling demonstration of Ruby's capabilities as a systems language.

## Sources

Where this goal was discovered:
- README.md (lines 22-23): "Pure ruby: Replace the gc (currently only statically linked in C component) with Ruby. Optionally/possibly replace libc dependency with direct syscalls."
- README.md (lines 27-28): "Build in an assembler and linker. A Ruby prototype x86 -> ELF binary assembler has shown we can drop the gas/ld dependency."
- docs/ARCHITECTURE.md (lines 99-103): Documents the garbage collector as "Mark-and-sweep garbage collector written in C" -- the sole C component
- docs/ARCHITECTURE.md (lines 170-171): Lists GCC as a dependency "for final assembly and linking"
- README.md (lines 55-60): Documents GC overhead concerns and improvement avenues, showing active thought about GC architecture

## Related Goals

- [SELFHOST](SELFHOST-clean-bootstrap.md): A pure Ruby runtime requires a clean bootstrap first, since the GC replacement must be compilable by the compiler itself
- [COMPLANG](COMPLANG-compiler-advancement.md): Improving spec compliance ensures the Ruby subset available for writing the GC and assembler is large enough

## Potential Plans

**GC Replacement Complexity Warning:** Replacing the C GC with Ruby is the hardest part of this goal, and the reason it has not been done. The fundamental problem is that a Ruby GC *itself produces garbage during execution* — the GC's own object allocations create new objects that need to be managed. This cannot be meaningfully tested under MRI (which has its own GC handling Ruby allocations transparently). Two possible approaches have been identified:

1. **Mark-on-create during GC:** Ensure any object allocated during a GC run is immediately marked as reachable. **Concern:** It is vital to ensure that the average number of objects created during a GC run does not exceed the average number of objects collected. This is not a given without careful design — an unbounded GC allocation rate would cause memory to grow without bound.

2. **Arena allocator for GC temporaries:** Switch the GC's own allocations to an arena allocator, so all GC-internal allocations are freed in bulk when the GC run completes. **Risk:** Care must be taken that no references to arena-allocated objects escape the GC run. Any objects that *should* survive the GC (i.e., are reachable from the program) must be allocated using the regular allocator, not the arena.

Plans attempting to address the GC replacement are highly valuable, but **must** account for these self-referential allocation problems. Naive prototyping will not surface the real difficulties.

Ideas for incremental plans that would advance this goal:
- Prototype a simple mark-and-sweep GC in Ruby, test it under MRI, then compile it with the compiler
- Build on the existing "Ruby prototype x86 -> ELF binary assembler" mentioned in README.md to create a minimal working assembler
- Profile GC allocation patterns during self-compilation to understand requirements for the Ruby GC replacement
- Implement the subset of libc functions actually used by compiled programs as Ruby wrappers around syscalls

---
*Status: GOAL*
