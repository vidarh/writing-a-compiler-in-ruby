# Range#bsearch must TERMINATE on a Float range. The impl uses integer-style bisection; once Integer/
# Float comparisons became real, `while lo < hi` actually ran on continuous/float ranges and could spin
# forever (esp. an infinite bound: mid = (-inf+1)/2 = -inf, mid+1 == mid → no progress). A no-progress
# break guard fixes termination (integer ranges always advance, so it never fires for them).
p((0..10).bsearch { |x| x >= 4 })          # 4  (integer, exact)
p((0..4).bsearch { |x| x <=> 5 })           # nil (integer find-any)
p((-2.0..3.2).bsearch { |x| x <=> 5 })      # nil (float range, must not hang)
p(((-1.0/0.0)..0.0).bsearch { |x| x != (-1.0/0.0) }.class)  # returns *something*, must not hang
p((1.0..3.0).bsearch { |x| x < 5 }.class)   # Float (terminates)
