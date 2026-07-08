# Object#define_singleton_method defines a method on one object alone (on its singleton/eigen class),
# from a block or a Proc/lambda passed as the second argument; the body closes over its defining scope.
# No body is an ArgumentError; a non-callable body is a TypeError. Verified vs MRI.
def try
  begin
    yield
    "no-raise"
  rescue => e
    e.class.to_s
  end
end

o = Object.new
o.define_singleton_method(:greet) { "hi" }
p(o.greet)                                       # "hi"
n = 5
o.define_singleton_method(:double) { n * 2 }     # closes over n
p(o.double)                                       # 10
o.define_singleton_method(:tw, ->(x) { x * 3 })  # lambda body given positionally
p(o.tw(4))                                        # 12
p(try { o.define_singleton_method(:bad) })        # "ArgumentError" (no body)
p(try { o.define_singleton_method(:bad2, "notproc") })  # "TypeError"

# defined only on this object: a sibling does not get it
o2 = Object.new
p(try { o2.greet })                               # "NoMethodError"
# (NOTE: respond_to?(:greet) still returns false here -- a separate gap: respond_to? does not consult
#  the define_method dispatch table -- so it is deliberately not asserted.)
