# Unparenthesized negative INTEGER literal times something: `-5 * x`. The tokenizer's `**`
# lookahead consumed a lone '*' during `-<digits>` handling and failed to unget it, dropping the
# multiply operator. `-5 * x` then mis-parsed as a call `-5(x)`, emitting the tagged literal -5
# (0xfffffff7) as an indirect call target -> SIGSEGV. The '*' is now restored when it is not `**`.
p(-5 * 100000)        # -500000
p(-5 * 3)             # -15
p(-5 * 10**3)         # -5000
x = 7
p(-5 * x)             # -35
p(-2 ** 12)           # -4096  (power precedence: -(2**12), still preserved)
p(-5 ** 2)            # -25
p(-5 * -3)            # 15
p((-5) * 100000)      # -500000  (parenthesized form unchanged)
a = -5 * 10**342
p(a.class)            # Integer  (big negative bignum, no crash)
