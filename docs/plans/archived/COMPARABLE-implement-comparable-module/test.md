# Test Specification: COMPARABLE — Implement Comparable Module

## Test Suite Location

All custom test files go in `spec/` using `_spec.rb` suffix, following
existing project conventions. Tests are run via `./run_rubyspec spec/`
which compiles and executes each spec through the compiler.

Specific files to create:

- `spec/comparable_operators_spec.rb` — Tests the Comparable module
  itself using a custom class that defines `<=>` and includes Comparable
- `spec/comparable_string_spec.rb` — Tests that String gains `<`, `<=`,
  `>`, `>=`, `between?` via Comparable inclusion
- `spec/comparable_symbol_spec.rb` — Tests that Symbol gains `<`, `<=`,
  `>`, `>=`, `==`, `between?` via Comparable inclusion

Upstream validation (do NOT create — already exists):

- `rubyspec/core/comparable/between_spec.rb` — Run as-is for validation
- `rubyspec/core/comparable/lt_spec.rb` etc. — Run as-is for validation

## Design Requirements

No refactoring is needed for testability. The design is inherently
testable because:

1. **Comparable is a pure module** — it depends only on `self.<=>` and
   integer comparison operators. No external services, no I/O, no
   global state.
2. **Module inclusion already works** — confirmed by
   `spec/include_simple_test_spec.rb`.
3. **Test classes define their own `<=>`** — no mocking needed. The
   rubyspec fixture pattern (`ComparableSpecs::Weird`) demonstrates
   this: define `<=>` in terms of an `@value` attribute, include
   Comparable, and all operators become testable via real objects.
4. **`should_receive` only works on Mock objects** in this compiler's
   mspec implementation, NOT on arbitrary objects. All custom specs
   MUST use real objects with real `<=>` implementations, not mocked
   `<=>` calls. This is a hard constraint of the test framework.

## Required Test Coverage

### A. Comparable Module Core (`spec/comparable_operators_spec.rb`)

Define a test class inline (before the `describe` block):

```ruby
class ComparableTest
  include Comparable
  attr_reader :value
  def initialize(v); @value = v; end
  def <=>(other); self.value <=> other.value; end
end
```

#### Happy-path scenarios

1. **`<` returns true when self is less** —
   `ComparableTest.new(1) < ComparableTest.new(2)` should be `true`

2. **`<` returns false when self is equal** —
   `ComparableTest.new(1) < ComparableTest.new(1)` should be `false`

3. **`<` returns false when self is greater** —
   `ComparableTest.new(2) < ComparableTest.new(1)` should be `false`

4. **`<=` returns true when less** —
   `ComparableTest.new(1) <= ComparableTest.new(2)` should be `true`

5. **`<=` returns true when equal** —
   `ComparableTest.new(1) <= ComparableTest.new(1)` should be `true`

6. **`<=` returns false when greater** —
   `ComparableTest.new(2) <= ComparableTest.new(1)` should be `false`

7. **`>` returns true when self is greater** —
   `ComparableTest.new(2) > ComparableTest.new(1)` should be `true`

8. **`>` returns false when self is equal** —
   `ComparableTest.new(1) > ComparableTest.new(1)` should be `false`

9. **`>` returns false when self is less** —
   `ComparableTest.new(1) > ComparableTest.new(2)` should be `false`

10. **`>=` returns true when greater** —
    `ComparableTest.new(2) >= ComparableTest.new(1)` should be `true`

11. **`>=` returns true when equal** —
    `ComparableTest.new(1) >= ComparableTest.new(1)` should be `true`

12. **`>=` returns false when less** —
    `ComparableTest.new(1) >= ComparableTest.new(2)` should be `false`

13. **`==` returns true when `<=>` returns 0** —
    `ComparableTest.new(5) == ComparableTest.new(5)` should be `true`

14. **`==` returns true for identity (same object)** —
    `a = ComparableTest.new(5); (a == a).should == true`

15. **`==` returns false when `<=>` returns non-zero** —
    `ComparableTest.new(1) == ComparableTest.new(2)` should be `false`

16. **`between?` returns true when self is within range** —
    `ComparableTest.new(5).between?(ComparableTest.new(1), ComparableTest.new(10))` should be `true`

17. **`between?` returns true when self equals min** —
    `ComparableTest.new(1).between?(ComparableTest.new(1), ComparableTest.new(10))` should be `true`

18. **`between?` returns true when self equals max** —
    `ComparableTest.new(10).between?(ComparableTest.new(1), ComparableTest.new(10))` should be `true`

19. **`between?` returns true when min equals max equals self** —
    `ComparableTest.new(5).between?(ComparableTest.new(5), ComparableTest.new(5))` should be `true`

20. **`between?` returns false when self is below min** —
    `ComparableTest.new(0).between?(ComparableTest.new(1), ComparableTest.new(10))` should be `false`

21. **`between?` returns false when self is above max** —
    `ComparableTest.new(11).between?(ComparableTest.new(1), ComparableTest.new(10))` should be `false`

#### Edge cases

22. **Negative values** — `ComparableTest.new(-5) < ComparableTest.new(-1)` should be `true`

23. **Large values** — `ComparableTest.new(999999) > ComparableTest.new(-999999)` should be `true`

24. **Zero-centered** — `ComparableTest.new(0) == ComparableTest.new(0)` should be `true`

#### Nil return from `<=>`

25. **`<` returns nil when `<=>` returns nil** — Define a class whose
    `<=>` returns nil. `a < b` should return `nil` (not crash, not
    raise). This validates the nil guard.

26. **`==` returns false when `<=>` returns nil** — Same nil-returning
    `<=>`. `a == b` should return `false`.

27. **`between?` with nil `<=>` does not crash** — Should return
    `false` (because `>=` on the first comparison returns nil, which
    is falsy, short-circuiting the `&&`).

### B. String Comparisons (`spec/comparable_string_spec.rb`)

These test that `include Comparable` on String is working and that
String's `<=>` drives correct comparison operators.

#### Happy-path scenarios

28. **`"a" < "b"` returns true** — Lexicographic less-than

29. **`"b" < "a"` returns false**

30. **`"a" <= "a"` returns true** — Equal strings

31. **`"a" <= "b"` returns true**

32. **`"b" <= "a"` returns false**

33. **`"b" > "a"` returns true** — Lexicographic greater-than

34. **`"a" > "b"` returns false**

35. **`"a" >= "a"` returns true** — Equal strings

36. **`"z" >= "a"` returns true**

37. **`"a" >= "z"` returns false**

38. **`"hello".between?("a", "z")` returns true**

39. **`"a".between?("b", "z")` returns false**

#### Edge cases

40. **String `==` still uses String's own implementation** — Verify
    `"hello" == "hello"` returns `true` (String's byte-compare `==`,
    not Comparable's `<=>` based one).

41. **Strings of different lengths** — `"ab" < "abc"` should be `true`
    (shorter string is less when prefix matches).

42. **Strings of different lengths reversed** — `"abc" > "ab"` should
    be `true`.

43. **Empty string comparison** — `"" < "a"` should be `true`.

44. **String compared to non-string with `<`** — `"a" < 1` should
    return `nil` (because `String#<=>` returns nil for non-String,
    and Comparable's `<` returns nil when `<=>` returns nil). This
    must NOT crash.

### C. Symbol Comparisons (`spec/comparable_symbol_spec.rb`)

#### Happy-path scenarios

45. **`:a < :b` returns true**

46. **`:b > :a` returns true**

47. **`:a <= :a` returns true**

48. **`:a >= :a` returns true**

49. **`:a == :a` returns true** — Same symbol object (identity AND
    `<=>` both return true).

50. **`:a != :b` returns true**

51. **`:a.between?(:a, :z)` returns true**

52. **`:z.between?(:a, :m)` returns false**

#### Edge cases

53. **Symbol `==` comes from Comparable** — `:a == :a` should return
    `true`. Since Symbol does NOT define its own `==`, this tests that
    Comparable's `==` correctly handles identity via `equal?`.

54. **Symbol compared to non-symbol** — `:a < "a"` should return `nil`
    (because `Symbol#<=>` returns nil for non-Symbol).

### D. Integer Non-Regression

These verify that Integer's own comparison operators are NOT
overwritten by Comparable's versions.

55. **Integer `<` still works** — `1 < 2` should be `true`

56. **Integer `>` still works** — `2 > 1` should be `true`

57. **Integer `==` still works** — `5 == 5` should be `true`

58. **Integer `between?` works** — `5.between?(1, 10)` should be
    `true`. (This tests that Integer gains `between?` from Comparable
    even though it defines its own `<`/`>`/etc.)

These can be included in `spec/comparable_operators_spec.rb` as a
separate `describe` block, or as a few assertions at the end.

### E. Upstream Rubyspec Validation

Run the existing rubyspec comparable specs as-is. Do NOT create new
files for these — just run them and document results.

59. **`rubyspec/core/comparable/between_spec.rb`** — Expected: PASS
    (2/2 tests). No mocks, no floats, no exceptions.

60. **`rubyspec/core/comparable/lt_spec.rb`** — Expected: partial.
    Tests using `should_receive` on real objects will fail (framework
    limitation). Tests using Float returns will fail.

61. **`rubyspec/core/comparable/gt_spec.rb`** — Same expectations as lt.

62. **`rubyspec/core/comparable/gte_spec.rb`** — Same expectations.

63. **`rubyspec/core/comparable/lte_spec.rb`** — Same expectations.

64. **`rubyspec/core/comparable/equal_value_spec.rb`** — Expected:
    identity test passes. Mock-dependent and exception tests will fail.

Document which specific tests pass/fail in each file. This
establishes a baseline.

### F. Bootstrap Non-Regression

65. **`make selftest` passes** — Verifies the compiler itself still
    works with the Comparable module loaded.

66. **`make selftest-c` passes** — Verifies the self-compiled compiler
    works.

## Mocking Strategy

**No mocking is needed.** All tests use real objects.

The Comparable module is a pure computation module — it calls
`self.<=>` and compares the result against 0 using Integer operators.
There are no external dependencies, no I/O, no network, no database.

Testing strategy:
- Define a simple class with `<=>` and `include Comparable`
- Construct instances with known `@value` fields
- Assert operator results directly

For the nil-return edge case (scenarios 25-27), define a second test
class whose `<=>` always returns nil:

```ruby
class ComparableNilTest
  include Comparable
  def <=>(other); nil; end
end
```

For String and Symbol tests, use literals directly — the classes
already define `<=>` and will gain operators from Comparable.

**Important:** Do NOT use `should_receive` on any object. The
compiler's mspec implementation only supports `should_receive` on
`Mock` objects, not on arbitrary instances. All assertions must use
real method calls with real return values.

## Invocation

```bash
# Run all custom Comparable specs (must exit non-zero on any failure):
./run_rubyspec spec/comparable_operators_spec.rb
./run_rubyspec spec/comparable_string_spec.rb
./run_rubyspec spec/comparable_symbol_spec.rb

# Run upstream rubyspec comparable suite:
./run_rubyspec rubyspec/core/comparable/

# Run all custom specs together:
./run_rubyspec spec/

# Run bootstrap validation:
make selftest
make selftest-c
```

Each `./run_rubyspec` invocation exits non-zero on failure:
- Exit 1 = test assertion failures
- Exit 2 = segfault or runtime crash
- Exit 3 = compilation failure

## Known Pitfalls

1. **Do NOT use `should_receive` on real objects.** The compiler's
   mspec helper only defines `should_receive` on the `Mock` class. If
   you call `obj.should_receive(:<=>)` on a `ComparableTest` instance,
   you will get "undefined method 'should_receive'". Use real `<=>`
   implementations instead.

2. **Do NOT test with Float values.** Float is not implemented in this
   compiler. Tests that create `0.0`, `-0.1`, or `1.0` will fail at
   compile time or produce incorrect results. All `<=>` return values
   in tests must be Integer (-1, 0, 1).

3. **Do NOT test `raise_error(ArgumentError)`.** The plan explicitly
   puts ArgumentError out of scope. The implementation returns nil
   instead of raising when `<=>` returns nil. Do not write assertions
   expecting exceptions from comparison operators.

4. **All spec files MUST use mspec format.** Every file must begin
   with `require_relative '../rubyspec/spec_helper'` and use
   `describe`/`it`/`.should` syntax. Plain `puts`-based tests will not
   work with `./run_rubyspec`.

5. **Define test classes BEFORE the `describe` block**, not inside
   `it` blocks. The `run_rubyspec` script wraps the `describe` block
   inside a function. Class definitions inside `it` may work, but
   defining them at the top level (after the require, before describe)
   is the established pattern (see `spec/include_simple_test_spec.rb`).

6. **Do NOT use `before(:each)` with instance variables in custom
   specs if avoidable.** The `run_rubyspec` script rewrites `@vars` to
   `$spec_vars` via sed, which works but adds fragility. Prefer
   creating fresh objects inside each `it` block instead.

7. **Do NOT expect Integer's operators to be replaced.** Integer
   defines its own `<`, `<=`, `>`, `>=`, `==`. The `__include_module`
   function only fills uninitialized vtable slots. Integer's operators
   will NOT change. Only `between?` is new for Integer (since Integer
   doesn't define it). Test accordingly.

8. **String `==` is NOT from Comparable.** String defines its own `==`
   at `lib/core/string.rb:222`. Comparable's `==` will not override
   it. Do not test `"a" == "a"` as evidence that Comparable's `==`
   works — test it as evidence that String's own `==` is preserved.

9. **Symbol `==` IS from Comparable.** Unlike String, Symbol does NOT
   define its own `==`. After `include Comparable`, Symbol's `==` will
   be Comparable's version (calling `<=>` and checking for 0). This is
   a meaningful distinction to test.

10. **The `between?` method calls `>=` and `<=` on self.** If the
    including class defines its own `>=`/`<=` (like Integer), those
    will be called instead of Comparable's. This is correct behavior
    but means `between?` is tested through possibly different code
    paths on Integer vs. ComparableTest.

11. **Watch for `nil` vs `false` confusion.** When `<=>` returns nil:
    - `<`, `<=`, `>`, `>=` return `nil` (not `false`)
    - `==` returns `false` (not `nil`)
    - Use `.should == nil` and `.should == false` precisely

12. **Run tests inside Docker.** The compiler targets i386. Use
    `make cli` to get a Docker shell, then run the test commands from
    within the container.

13. **Do NOT modify any file in `rubyspec/`.** Tests in `rubyspec/`
    are upstream specs and must not be edited. Only run them as-is.
