# Fixnum Method Migration to Integer

## Goal

Migrate each of the 10 critical Fixnum methods to Integer, ensuring they work for BOTH:
1. Tagged fixnums (when called via inherited Integer method)
2. Heap integers (existing bignum functionality)

## Strategy

For each method:
1. Remove from Fixnum
2. Verify selftest-c fails (confirms criticality)
3. Update Integer version to handle tagged fixnums
4. Verify selftest-c passes
5. Commit working version
6. Move to next method

## Method Migration Order

Start with simplest, build up to most complex:

1. `__get_raw` - Foundation method used by others
2. `<` - Simple comparison
3. `>` - Simple comparison
4. `<=` - Simple comparison
5. `>=` - Simple comparison
6. `<=>` - Complex comparison (uses <, >)
7. `%` - Modulo
8. `-` - Subtraction
9. `*` - Multiplication
10. `/` - Division
11. `class` - Most critical, do last

## Progress Tracking

- [x] __get_raw - ✅ Removed (Integer version works for both representations)
- [x] < - ✅ Removed (updated Integer to use __get_raw directly)
- [x] > - ✅ Removed (updated Integer to use __get_raw directly)
- [x] <= - ✅ Removed (updated Integer to use __get_raw directly)
- [x] >= - ✅ Removed (updated Integer to use __get_raw directly)
- [x] <=> - ✅ Removed (Integer version uses __get_raw for both operands)
- [x] % - ✅ Removed (updated Integer with Ruby sign-handling semantics)
- [x] - - ✅ Removed (Integer version handles overflow detection)
- [ ] * - ❌ BLOCKED (Integer version causes FPE during compilation)
- [x] / - ✅ Removed (updated Integer with to_int conversion)
- [ ] class - Not attempted (most critical, returns Fixnum for compiler)

## Current State

- Fixnum: **2 methods remaining** (*, class) - down from 10!
- Fixnum size: ~45 lines (down from 85 lines)
- Integer: 58 methods (updated 8 methods to handle both representations)
- selftest-c: 0 failures ✅

## Blocked Methods

### `*` (multiplication)
- **Status:** Cannot be removed yet
- **Issue:** Removing causes FPE at ~403000 __cnt during selftest-c
- **Integer version:** Has to_int conversion and proper dispatch
- **Root cause:** Unknown - needs investigation
- **Hypothesis:** May involve overflow handling or __add_with_overflow during compilation

### `class`
- **Status:** Not attempted (known to be critical)
- **Issue:** Compiler uses class identity checks during compilation
- **Requirement:** Must return `Fixnum` for tagged integers
- **See:** docs/FIXNUM_CLASS_METHOD_INVESTIGATION.md

## Summary

Successfully migrated 8 of 10 critical methods from Fixnum to Integer:
- All comparison operators (<, >, <=, >=, <=>)
- Modulo (%)
- Subtraction (-)
- Division (/)
- __get_raw helper

Integer methods were updated to handle both tagged fixnums and heap integers correctly.

Remaining work:
- Investigate why * cannot be removed (FPE during compilation)
- Document that class cannot be removed (compiler requirement)
