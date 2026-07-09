# COREMARSHAL via a custom AST serializer — SPIKE FINDINGS (VALIDATED)

*2026-07-09. Prototype: `ast_serializer_spike.rb` in this directory (MRI-only measurement patch —
NOT in the compile path; opt-in via `COREMARSHAL_AST=<cachefile> ruby -r`).*

## Result

The per-spec compile cost is dominated by re-parsing/re-compiling `lib/core` (`core/core.rb`) on every
invocation. The 2026-06-26 COREMARSHAL spike cached the parsed AST via MRI `Marshal` (~42%) but deferred
because productionising needs the *self-hosted* compiler to run Marshal, which requires dynamic-ivar
reflection (`pure_ruby_marshal` uses `instance_variable_get/set` etc. that lib/core lacks).

**This spike removes that dependency.** A **purpose-built pure-Ruby serializer** for the small, closed set
of AST types — `AST::Expr` (elements + `@position`), `Scanner::Position` (filename/lineno/col),
`Scanner::ScannerString` (string + `@position`), and `Array`/`String`/`Symbol`/`Integer`/`nil`/`bool` —
reconstructs everything via **public constructors + accessors only, no reflection**. (`@extra` is set only
during transforms, never in the parsed AST, so it is skipped.)

- **Correctness:** compiling a program (which inlines all of lib/core) with the cache vs without produced
  a **BYTE-IDENTICAL `.s`** (601,661 lines). ✓
- **Speedup:** baseline ~9.53s → cached ~6.32s = **~34% faster compile** (saves ~3.2s/compile).
  (Slightly less than MRI Marshal's ~42% because the naive format is larger / slower to load; a tighter
  format would close the gap. Still the dominant win, and it needs NO reflection.)
- **Self-host-safe primitives:** `[x].pack("N")` / `str.unpack("N")` round-trip correctly when COMPILED;
  `String#unpack`, `File.binread/binwrite`, `String#to_sym`, `String#[pos,n]`, `bytesize` all exist in
  lib/core. So the serializer is a realistic candidate to self-compile (unlike full `pure_ruby_marshal`).

**This custom serializer is a TEMPORARY / INTERIM STAGE only** (user directive 2026-07-09): it banks the
perf win NOW to make all further tests/dev cheaper, but it does NOT replace the real goal. The ongoing job
is **full Marshal** via `pure_ruby_marshal`, which needs the dynamic-ivar reflection
(`instance_variable_get/set` / `instance_variables` / `const_get` / `send` + the `ivar` codegen support).
Once that lands and `pure_ruby_marshal` is ported into lib/core, it REPLACES this serializer (and also
passes the core/marshal specs). Dynamic-ivar reflection is therefore the PRIMARY ongoing track, not a
lower-priority one — this bridge just runs first because it is cheap and unblocks nothing else.

## Productionisation plan (must work in BOTH MRI and self-hosted — no MRI-only landing)

1. Verify the whole serializer SELF-COMPILES (compile it under the self-hosted compiler / `selftest-c`);
   fix any lib/core gaps it surfaces.
2. Move the serializer into compiler source (a new file `require`d by `parser.rb`).
3. Wire the cache into `Parser#require("core/core.rb")` with **invalidation** on lib/core change
   (mtime or content hash of the core sources) so a stale cache can never be used.
4. Gate: `make selftest` + `make selftest-c` Fails:0, byte-identical `.s`, crash battery clean.
5. Optional: tighten the binary format (smaller/faster load) to approach the ~42% ceiling.

See task COREMARSHAL-via-custom-AST-serializer. The MRI-only spike patch here stays as measurement
evidence only, per the never-diverge rule ([[compiler_mri_selfhost_never_diverge]]).
