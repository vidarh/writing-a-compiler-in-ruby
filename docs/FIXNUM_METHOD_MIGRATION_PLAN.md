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

- [ ] __get_raw
- [ ] <
- [ ] >
- [ ] <=
- [ ] >=
- [ ] <=>
- [ ] %
- [ ] -
- [ ] *
- [ ] /
- [ ] class

## Current State

- Fixnum: 10 methods, 85 lines
- Integer: 58 methods
- selftest-c: 0 failures ✅
