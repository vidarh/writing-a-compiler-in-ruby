# Float#next_float / #prev_float via libm nextafter(self, +/-Infinity), called directly. Covers the
# IEEE edges: Infinity is its own next_float, Float::MAX steps to Infinity, 1.0.next_float == 1.0+EPSILON,
# and next_float/prev_float round-trip.
p(1.0.next_float == 1.0 + Float::EPSILON)          # true
p(0.0.next_float > 0.0)                            # true
p(Float::INFINITY.next_float == Float::INFINITY)   # true
p(Float::MAX.next_float == Float::INFINITY)        # true
p((-Float::INFINITY).next_float == -Float::MAX)    # true
p(1.0.next_float.prev_float == 1.0)                # true
p((-1.0).next_float == -1.0 + Float::EPSILON/2)    # true
p(5.0.prev_float < 5.0)                            # true
