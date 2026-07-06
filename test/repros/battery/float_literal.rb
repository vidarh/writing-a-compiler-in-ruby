# Float literals must compile (SELF-HOSTED too) to a usable Float object. Previously the tokeniser used
# String#to_f, which is stubbed in the self-hosted runtime -> every literal became 0.0 / selftest-c died.
# Now the literal's decimal string is emitted as `.double <string>` and gas converts it. Value
# correctness (via arithmetic / to_s) is guarded once Phase 1 items 2-4 land; this guards compile+run.
x = 1.5
y = 3.14159
z = 1.5e10
w = 0.0
p x.class          # Float
p y.class          # Float
p z.class          # Float
p w.class          # Float
p [x, y, z].length # 3
