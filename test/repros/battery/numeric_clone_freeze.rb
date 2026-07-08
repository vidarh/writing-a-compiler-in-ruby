# Numbers are immutable value objects: #clone returns self and they are always frozen. An explicit
# clone(freeze: false) -- a request for an unfrozen copy -- is an ArgumentError; clone(freeze: true) and
# clone(freeze: nil) just return self. Verified vs MRI.
def try
  begin
    yield
    "no-raise"
  rescue => e
    e.class.to_s
  end
end
p(5.clone.equal?(5))                 # true
p(5.clone(freeze: true).equal?(5))   # true
p(5.clone(freeze: nil).equal?(5))    # true
p(try { 5.clone(freeze: false) })    # "ArgumentError"
p(try { Rational(1, 2).clone(freeze: false) })  # "ArgumentError"
p(5.clone.frozen?)                   # true
