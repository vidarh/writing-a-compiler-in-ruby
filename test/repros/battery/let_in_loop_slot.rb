# A :let nested inside a loop body must allocate its variables in slots ABOVE the enclosing method's
# own locals, not aliasing them. ControlScope (created for while/until bodies) inherited a base
# Scope#lvaroffset that returned 0 instead of delegating to @next, so a let-var inside the loop was
# assigned the offset of the method's first local and clobbered it. Two manifestations:
#   - `arr.each do |a, b|` auto-splats each pair, and Array#each's `yield(*el)` wraps the call in a
#     :let (__splat_a); the let clobbered the loop counter -> corruption after the first element.
#   - any explicit `yield(*local)` inside a while loop clobbered the counter.
# Verified vs MRI.

res = []
[[1, 2], [3, 4], [5, 6]].each do |a, b|
  res << a
  res << b
end
p(res)   # [1, 2, 3, 4, 5, 6]

def go
  i = 0
  while i < 3
    el = [i, i + 10]
    yield(*el)
    i += 1
  end
end
seen = []
go { |a, b| seen << a; seen << b }
p(seen)  # [0, 10, 1, 11, 2, 12]
