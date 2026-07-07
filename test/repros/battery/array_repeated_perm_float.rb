# Regression: Array#repeated_permutation(n) must truncate a Float n to an Integer (MRI: "truncates
# Float arguments"). Without it, `current.length == n` (n=3.7) never holds -> infinite recursion ->
# stack overflow / SIGSEGV. This surfaced only once Float#>= became real (the `if n >= 0` guard used
# to hit the Float#>= stub -> false -> recursion skipped, so it FAILED instead of crashing).
p [1,2,3].repeated_permutation(3.7).to_a.length   # 27 (3.7 -> 3)
p [1,2].repeated_permutation(2.9).to_a.length      # 4  (2.9 -> 2)
p [1,2,3].repeated_permutation(2).to_a.length      # 9  (plain Integer still works)
p [1,2,3].repeated_permutation(0).to_a.length      # 1  ([[]])
