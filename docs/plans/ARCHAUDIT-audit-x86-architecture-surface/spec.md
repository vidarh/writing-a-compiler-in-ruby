ARCHAUDIT
Created: 2026-02-25

# Audit x86 Architecture-Specific Surface and Define Backend Interface

[MULTIARCH] Enumerate every x86-32-specific constant, register reference, instruction pattern, and calling convention assumption across all compiler source files. Classify each by coupling level. Produce `docs/x86-backend-interface.md` that maps the complete architecture surface and defines the minimum interface a second backend must implement.

## Goal Reference

[MULTIARCH](../../goals/MULTIARCH-architecture-support.md): This audit is the prerequisite for every other MULTIARCH plan. No backend abstraction can be designed or implemented without knowing precisely what needs to be abstracted — the full extent of x86-specific code spread across 12 files.

## Prior Plans

No prior plans in `docs/plans/` or `docs/plans/archived/` target MULTIARCH directly. The [LOCALDEV](../../plans/archived/LOCALDEV-docker-free-local-compilation/spec.md) plan (IMPLEMENTED) addressed the development environment by enabling local compilation without Docker. EXCMOD mentions MULTIARCH as a secondary goal but its scope is exception extraction, not architecture abstraction. No plan has attempted to enumerate or document the x86 architecture surface.

## Root Cause

The compiler assumes 32-bit x86 at every level of code generation, and these assumptions are scattered across 12 source files rather than isolated in one backend module:

- **[emitter.rb](../../emitter.rb)** (748 lines): `PTR_SIZE = 4` (line 29), returns `:ebx` as the numargs register (line 133), `:esp` as stack pointer (line 141), emits `pushl %ebx` for numargs (line 644), 16-byte stack alignment constant (line 344), `%ebp`-based frame addressing (`PTR_SIZE*(aparam+2)(%ebp)`, lines 97, 105), AT&T assembly syntax throughout
- **[regalloc.rb](../../regalloc.rb)** (378 lines): Hardcodes the register file as `[:edx, :ecx, :edi]` (line 119), `@selfreg = :esi` (line 122), `@caller_saved = [:edx, :ecx, :edi]` (line 125) — all x86 calling convention decisions
- **[compiler.rb](../../compiler.rb)** (1640 lines): 47 x86 register symbol references
- **[compile_calls.rb](../../compile_calls.rb)** (515 lines): 21 x86 register references, `Emitter::PTR_SIZE * (args.length+4)` for stack frame layout
- **[compile_control.rb](../../compile_control.rb)** (365 lines): 16 x86 register references
- **[saveregs.rb](../../saveregs.rb)**: 25 x86 register references (callee-saved register list)
- **[compile_arithmetic.rb](../../compile_arithmetic.rb)**, **[compile_class.rb](../../compile_class.rb)**, **[classcope.rb](../../classcope.rb)**, **[output_functions.rb](../../output_functions.rb)**, **[peephole.rb](../../peephole.rb)**, **[trace.rb](../../trace.rb)**: Additional architecture-specific references

Total: **~199 x86 register symbol references** across **12 compiler source files**, plus `PTR_SIZE` usage in 14+ locations, plus assembly instruction names (`movl`, `pushl`, `popl`, `cmpl`, `leal`, etc.) embedded throughout.

The root cause is that the compiler was written from the start as a single-architecture tool. There is no backend abstraction layer, no interface definition, and no separation between frontend (parsing, scoping, AST construction) and backend (register allocation policy, instruction selection, calling convention). This is exactly what README.md:26-27 identifies as the needed "clean separation of concerns."

**Why an audit must precede extraction**: Three classes of coupling exist in the codebase, and mixing them in an extraction plan causes regressions:
1. **Pure backend** — constants and patterns that belong entirely in an architecture module (PTR_SIZE, register names in regalloc.rb, AT&T syntax in emitter.rb)
2. **Frontend with backend leakage** — places where the frontend generates register-specific code because no abstraction exists yet (47 references in compiler.rb are a symptom of this)
3. **Intentionally shared** — generic patterns that happen to use x86 types because they're the only type available (the `to_operand_value` helper, for example, works generically for any register if registers are modeled differently)

Without classifying every reference into these three buckets, any extraction plan risks moving "shared" code into a backend module (breaking the frontend) or leaving "pure backend" code in the frontend (defeating the abstraction). The audit produces this classification.

## Infrastructure Cost

Zero. This is a search-and-document plan. No code is modified, no files are deleted, no build system is changed. The deliverable is a single new file in `docs/`. Validation is trivial: `make selftest` and `make selftest-c` should produce identical results before and after (no code changes = no regression risk).

## Scope

**In scope:**

1. **Search every compiler source file** for architecture-specific references:
   - `PTR_SIZE` — pointer size constant
   - Register symbols: `:eax`, `:ebx`, `:ecx`, `:edx`, `:esi`, `:edi`, `:esp`, `:ebp`, `:st0`
   - Assembly instruction names: `movl`, `pushl`, `popl`, `cmpl`, `addl`, `subl`, `imull`, `idivl`, `leal`, `jmp`, `je`, `jne`, `call`, `ret`, etc.
   - Calling convention assumptions: caller-saved vs callee-saved lists, argument push order, return value register, numargs convention
   - Stack frame layout constants: `4(%ebp)`, `-4(%ebp)`, frame size arithmetic
   - 16-byte alignment assumptions

2. **Classify each reference** into one of three buckets:
   - **Backend-only**: Can be moved to a backend module without touching the frontend (e.g., register lists in regalloc.rb, PTR_SIZE in emitter.rb)
   - **Frontend-leaked**: Frontend logic that uses backend specifics directly — must be refactored so the frontend calls an abstract backend method instead (e.g., compiler.rb emitting `:eax` directly)
   - **Generic/shared**: Code that works for any architecture and should not move (e.g., `to_operand_value` which works generically if Register objects are used consistently)

3. **Define the minimum backend interface**: Based on the classification, produce a proposed API that a backend module must implement. This includes:
   - Architecture constants: `ptr_size`, `word_size`
   - Register table: `return_reg`, `self_reg`, `numargs_reg`, `stack_ptr`, `frame_ptr`, `scratch_regs`, `callee_saved`, `caller_saved`
   - Stack frame helpers: `local_var_offset(n)`, `param_offset(n)`, `align_stack(n_args)`
   - Instruction names: `mov_instr`, `push_instr`, `pop_instr`, `compare_instr` (for the peephole optimizer's patterns)

4. **Produce `docs/x86-backend-interface.md`**: A document containing:
   - The complete audit table (file, line, reference, classification, notes)
   - Summary metrics: total references per file, per class, coupling severity
   - The proposed backend interface (method/constant names with types)
   - A prioritized extraction order: which files to start with to minimize coupling entanglement
   - The proposed directory layout for a future `backends/` module

**Out of scope:**
- Implementing any backend module or abstraction (that is the next plan)
- Modifying any `.rb` file
- Changing the build system
- Extracting any code

## Expected Payoff

**Immediate:**
- MULTIARCH gains its first active plan and concrete forward progress
- The audit table immediately reveals which files are most entangled with x86 specifics, guiding where to invest effort
- The proposed interface definition gives the next extraction plan a concrete spec to implement against
- Summary metrics enable measuring progress as extraction proceeds

**Downstream (MULTIARCH):**
- The backend interface document becomes the contract that x86-32 and x86-64 backends must implement
- The prioritized extraction order tells the next plan exactly which files to start with (likely: `regalloc.rb` and `emitter.rb` — high concentration, already nearly self-contained)
- Future plans can directly cite `docs/x86-backend-interface.md` as their specification rather than re-doing this research

**Downstream (CODEGEN, PURERB):**
- A documented backend interface clarifies what the peephole optimizer must know about registers (enabling safer peephole rules)
- The architecture abstraction is a prerequisite for the Ruby assembler/linker mentioned in README.md:27-28

## Proposed Approach

1. **Enumerate references by file**: Using `grep` with the register and instruction name patterns, produce a raw reference list for each of the 12 files. Count total references per file to identify concentration.

2. **Read each file's context**: For each reference, read the surrounding 10-15 lines to understand WHY that file needs the x86 constant or register name. This determines the classification (backend-only vs frontend-leaked vs generic).

3. **Identify logical groupings**: Group references into:
   - **Register policy** (which registers are available, caller/callee-saved): concentrated in regalloc.rb
   - **Stack frame layout** (parameter addressing, local variable addressing): concentrated in emitter.rb, used in compiler.rb
   - **Instruction set** (AT&T mnemonics): concentrated in emitter.rb output_functions.rb, peephole.rb
   - **Calling convention** (argument order, return value, numargs): split between emitter.rb, compile_calls.rb, compiler.rb

4. **Propose the backend interface**: For each logical grouping, define an abstract method or constant that a backend module should provide. Name them descriptively (avoid `eax` in interface names — use `return_register`, `self_register`, etc.)

5. **Write the document**: Produce `docs/x86-backend-interface.md` with the audit table, summary, interface definition, and extraction roadmap.

## Acceptance Criteria

- [ ] `docs/x86-backend-interface.md` exists

- [ ] The document contains an audit table with one row per distinct architecture-specific reference location, with columns: File, Line, Reference, Classification (Backend/Frontend-Leaked/Generic), Notes

- [ ] The audit covers all 12 identified files: `emitter.rb`, `regalloc.rb`, `compiler.rb`, `compile_calls.rb`, `compile_control.rb`, `saveregs.rb`, `compile_arithmetic.rb`, `compile_class.rb`, `classcope.rb`, `output_functions.rb`, `peephole.rb`, `trace.rb`

- [ ] The document includes a per-file summary table showing reference count and dominant classification for each file

- [ ] The document defines a proposed backend interface with at minimum: pointer size constant, register table (return/self/numargs/stack/frame/scratch/callee-saved/caller-saved), stack frame offset helpers, and instruction name aliases for the peephole optimizer

- [ ] The document includes a prioritized extraction order (which files should be extracted first, with rationale)

- [ ] `make selftest` passes (no code was changed, this is a sanity check)

---
*Status: PROPOSAL - Awaiting approval*
