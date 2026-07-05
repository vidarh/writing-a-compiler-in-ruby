# Canonical regression repros

Small standalone programs that reproduced (or still reproduce) specific compiler
bugs. Compile with `./compile test/repros/<file>` and run `out/<file>`.
Promoted from tmp/ (gitignored) so they survive purges; referenced from commit
messages and docs/KNOWN_ISSUES.md.

| File | What it exercises | Status |
|---|---|---|
| bk6.rb | Nested `break` unwinds to the DEFINING activation (expected [1,2]) | fixed (c6d1f4f nested envs) |
| hop1.rb | Hop-chained env read must be typed :object (`false && ...` truthiness) | fixed (lookup_type hop unwrap) |
| ac2.rb | Block-local shadowing an outer name (possible_callm lvar-index bug) | fixed (metaclass_spec fix) |
| mc6.rb | Accumulated-context metaclass crash companion | fixed |
| blk1.rb | Block semantics matrix: `&b` param, `yield`, `block_given?` across nesting | fixed (63b5875 __callblk__) |
| ie1.rb | instance_exec must not eat first arg as blkarg (expected [1, 2, 42] / 1) | fixed (17dffc5) |
| rat1.rb | Rational arithmetic/comparison/rounding, incl. Integer-promoted mixed ops | feature (full Rational impl) |
| cx1.rb | Complex exact arithmetic (+ - * == conjugate abs2 rect), Integer coercion | feature (Complex exact subset) |
| tor1.rb | String#to_r parses leading rational literals (whitespace/junk tolerant) | feature (String#to_r) |
| enum1.rb | Block-less Array iterators return an Enumerator (each_index/find/sort_by/…) | feature (block-less guards) |
| st5.rb | Exception containment ESCAPE: alias+def-in-block redefined `Integer#<=>` raising escapes the it-rescue | OPEN (KNOWN_ISSUES active 3) |
| pm1.rb | Pattern binding (`in [a, 1] if a >= 0`) inside a block: `a` not env-captured | OPEN (KNOWN_ISSUES active 2) |
