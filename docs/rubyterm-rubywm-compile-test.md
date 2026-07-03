# Compiling rubyterm and rubywm — issue catalogue

**Date:** 2026-07-03. **Branch:** `test-rubyterm-rubywm`.

Goal: use two real projects (`~/Desktop/Projects/ruby-term` — the rubyterm gem —
and `~/Desktop/Projects/wm` — rubywm) as compiler test loads, exercising the
compiler in ways rubyspec doesn't. The projects were NOT modified; workarounds
live in scratch copies / shim files (see "Test setup" below). Every fix below
passed the full gate (selftest + selftest-c, 0 fails) before being committed.

## Headline status

| Target | Compiles | Links | Runs |
|---|---|---|---|
| rubyterm engine (`lib/rubyterm/engine.rb`, no X11) | ✅ | ✅ | ✅ text, control chars, tabs, cursor, cell storage all verified correct; CSI dispatch blocked by String#[] semantics (below) |
| rubyterm full (X11 + skrift ×4 + pty/console/toml shims) | ✅ (with 1-line skrift-color workaround) | ✅ (3 MB) | ❌ startup SIGSEGV in X11::Type (class-ivar issue below) |
| rubywm (X11 + yaml/logger/drb shims) | ✅ (with 1-line ternary workaround) | ✅ (2.5 MB) | ❌ same X11::Type blocker |
| ruby-x11 gem alone (`require "X11"`) | ✅ | ✅ | ❌ same blocker |

## Fixed on this branch (found via these projects)

All reduced test cases verified against MRI; targeted rubyspec runs show no
regressions and clear wins (language/case: CRASH → 37 pass; hash/default_proc:
1 → 7 pass; string/slice: 42 → 47 pass).

1. **bb2c014** — shunting: after a plain grouping paren, `reduce(@opcall2)` (pri 9)
   popped any pending infix with pri > 9, so `a + (b).c` parsed as `(a + (b)).c`
   (while `a << (b).c`, pri 8, was fine). Hit: palette.rb's
   `PALETTE_BASIC + ... + (8..244).step(10).map{...}`.
2. **28f0b43** — `Hash#default_proc` / `default_proc=` / `Hash.new { |h,k| ... }`
   were missing. Hit: charsets.rb.
3. **64ff520** — `\uXXXX` / `\u{...}` string escapes produced the literal char `u`.
   Now UTF-8-encoded, byte-identical to MRI. Hit: charsets.rb.
4. **b45c553** — endless/beginless ranges: treeoutput `.compact` dropped the nil
   operand, so `(2..)` was `Range.new(2)` (arity error) and `(..5)` silently became
   `5..`(!). Also nil-endpoint handling in `Array#__range_get`, `Array#slice!`
   (+ its negative-inclusive-end bug), `String#[]`, `String#slice!` (which also
   gained Range/1-arg forms), and two-arg `String#[start, len]` (didn't exist).
   Hit: termbuffer.rb `enforce_height` (`@chars.slice!(@h..)`), utf8decoder.rb.
5. **4a0ca6e** — `obj[y] ||= v` with a variable index compiled the index as a
   method call on self (`undefined method 'y'`): compile_assign's arg wrap treated
   any leading Symbol as an unwrapped node. Hit: TermBuffer#set.
6. **a038bb8** — **broad**: a local assigned inside a `case/when` body in a method
   or top-level scope compiled as a method call (`case ch; when 8; j = 42; p j` →
   "undefined method 'j'"). find_vars' :case flatten was gated on `in_lambda`;
   the generic path drops the first when-clause and the first statement of later
   bodies. Also fixed: the `else` group is a separate AST element (n[3]) and was
   never scanned — the selftest gate caught that as a tokenizer regression before
   commit. Hit: Term#handle_control. (language/case_spec: segfault → 37 pass.)
7. **ee9cb58** — regexp POSIX bracket classes `[[:alpha:]]` etc. never matched:
   `__posix?` existed but was unreachable, all three pattern scanners ended the
   class at `:]`'s `]`, and the name dispatch couldn't distinguish
   alnum/alpha/ascii or print/punct. Hit: escapeparser.rb CSI terminator
   (`/[[:alpha:]]|[@]/`).
8. **2768323** — in a class/module body, self-dispatch after an argument build
   went through a stale `%esi` (reload_self emitted nothing for `[:global, Name]`
   self), so calling an INHERITED class method in a subclass body failed:
   `class Int8 < BaseType; config("c",1); end` → "undefined method 'config'".
   Hit: ruby-x11 type.rb (blocked the whole X11 stack at line 1).
9. **0e8eb6c** — parser: `when :sym; then body` (MRI-legal `;` before `then`)
   was a parse error. Hit: keymap.rb. Same commit: "Unable to open" build errors
   now print the require name instead of a strconst AST dump.

## Open issues (catalogued, NOT fixed)

### O1. String#[] returns an Integer byte (Ruby 1.8 semantics) — DEEP
`s[-1]` / `s[i]` return the byte value, not a 1-char String. rubyterm's Term
does `cmd = s[-1]; CSI_MAP[cmd]` (string keys) and `case s[-1] when "A"...` —
every branch silently misses, so all CSI sequences (cursor movement, SGR, erase)
are no-ops. This is the single blocker for the terminal engine being *usable*.
Flipping it interacts with `?x` char literals (Integers when self-hosted) and
byte-oriented String throughout lib/core — a coordinated 1.9-semantics migration,
not a spot fix. (Related known issue: byte-length vs char-length, e.g.
`" ".length` == 2.)

### O2. Class-level ivars written through an inherited class method corrupt the heap — DEEP; blocks all X11
```ruby
class BaseType
  def self.config(d, b); @directive, @bytesize = d, b; end
end
class Int8 < BaseType; config("c", 1); end   # ivar writes with self == Int8
```
Class objects are `[6 metadata][vtable]`; slot-based ivar writes on a class
object land on metadata/method pointers. 7842394 routed the static
`def self.foo; @x` case to `__classivar__` globals, but a class method inherited
from a superclass writes ivars on a *runtime-varying* self (each subclass), which
the static routing can't express. Result: heap corruption → the next
`__new_class_object` (X11::Form) returns garbage → SIGSEGV at startup
(`movl $1, (%ecx)` signature). This is the current wall for ruby-x11, and hence
rubywm and full rubyterm. Needs a runtime class-ivar mechanism (e.g. a per-class
ivar table hanging off class-object metadata).

### O3. Multi-line ternary continuation — parser
```ruby
target = @fullscreen ? (a || b)
                     : (c || d)     # wm/window.rb:216 — MRI-legal
```
"Missing value in expression / ternalt". A pending `?` must suppress the
newline statement break. Workaround: join onto one line.

### O4. `{ key: v || w }` — label colon vs `||`/`&&` precedence — parser
`{ color: @cpal[i] || [0,0,0,255] }` parses as `(color: @cpal[i]) || [...]`
("Literal Hash must contain key value pairs"). ternalt pri 7 vs `||` pri 6 —
same delicately hand-tuned pri family as the known won't-fix
assignment-vs-comparison issue; the clean fix is lexing `label:` as a distinct
token (MRI's tLABEL) instead of reusing ternalt. Workaround: parenthesize the
value. Hit: skrift-color renderer.rb:131.

### O5. `module_function` (argless) unsupported + statement-swallowing — parser/compiler
The no-op stub means `CharWidth.width` (defined under argless `module_function`)
doesn't exist as a module method. Worse, a bare `module_function` at statement
level *swallows the following statements as call arguments* (paren-less call
across newline), so `module_function` + `X = 1` mis-nests. Needs `private`-style
parser handling + eigenclass duplication of subsequent defs. Workaround used in
the test harness: reopen the module and `def self.width...`.

### O6. Missing stdlib for these projects
- `pty` (C ext; fork/execve/pipe infra exists per subprocess work — a pure
  s-expr PTY via posix_openpt/grantpt/unlockpt is feasible but is a feature project)
- `io/console` (raw!/echo=/winsize)
- `toml-rb` (pure-Ruby gem; untested beyond require)
- `yaml`, `logger`, `drb/drb`, `drb/unix`, `shellwords` (rubywm; shimmed —
  shellwords and logger would be easy real additions to lib/)
- `bundler/setup` — projects use Bundler; under AOT it should be a no-op shim
  on the include path.

### O7. Minor / observed along the way
- `Object#inspect` doesn't include instance variables (`#<T:0x...>` only).
- `when 4: body` (1.8 colon form) still accepted and mis-groups a trailing
  `when`; MRI 3.x rejects it outright. Low priority.
- run_rubyspec `core/array/slice_spec.rb` fails at harness level
  ("wrong number of arguments (given 0, expected 2)") on master AND this
  branch — pre-existing, unrelated to the slice fixes.
- `./compile` joins ARGV with spaces — `-I` paths containing spaces break
  (hit via "Link to src" symlinks; worked around with space-free symlinks).

## Test setup (for reproduction)

Scratch dir: `$CLAUDE_JOB_DIR/tmp`-adjacent scratchpad; the durable pieces are:
- Shims (`shims/`): `bundler/setup.rb`, `logger.rb`, `yaml.rb`, `drb/{drb,unix}.rb`,
  `pty.rb`, `io/console.rb`, `toml-rb.rb`, `shellwords.rb` — all no-op/minimal,
  clearly marked "shim".
- Engine harness: NullSink + TermBuffer/TrackChanges/Term wiring modeled on
  rubyterm's own test_ansibackend.rb; feeds bytes via `each_codepoint`+`putchar`
  (Term#feed's bare `rescue StandardError` otherwise hides every failure —
  worth remembering when testing).
- Compile lines:
  - engine: `./compile <ruby-term>/lib/rubyterm/engine.rb -I .`
  - full: `./compile driver.rb -I . -I <ruby-term>/lib -I <ruby-x11>/lib -I shims -I <skrift>/{skrift,skrift-x11,skrift-boxdrawing,skrift-color}/lib`
  - rubywm: `./compile <wm-copy>/rubywm.rb -I . -I shims -I <ruby-x11>/lib -I <wm-copy>`
- Project-source workarounds (in scratch COPIES only, never the real trees):
  wm/window.rb:216 ternary joined to one line (O3); skrift-color renderer.rb:131
  value parenthesized (O4).

## Recommended next steps
1. Full `make specs-parallel` sweep before merging this branch (transform.rb was
   touched; the case/when fix is broad and should move language/ numbers).
2. O2 (runtime class ivars) is the highest-leverage fix: it unblocks the entire
   X11 stack for both projects and is a ubiquitous Ruby pattern.
3. O1 (String#[] char semantics) is the second wall; plan as a coordinated
   migration (String#[], ?x literals, lib/core byte-string assumptions).
4. Easy wins: real `logger`/`shellwords` in lib/, `bundler/setup` no-op stub.
