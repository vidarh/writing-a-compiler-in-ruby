# Integer.try_convert returns an Integer argument as-is, nil for an argument that doesn't respond to
# #to_int, and otherwise the #to_int result -- which must be an Integer or nil. Any other #to_int result
# is a TypeError naming both classes ("can't convert X to Integer (X#to_int gives Y)"); #to_int is called
# without rescuing. Verified vs MRI.
class GoodInt; def to_int; 42; end; end
class BadInt; def to_int; "x"; end; end
class NilInt; def to_int; nil; end; end
def try
  begin
    yield.inspect
  rescue => e
    e.class.to_s + ": " + e.message
  end
end
p(Integer.try_convert(5))              # 5
p(Integer.try_convert(GoodInt.new))    # 42
p(Integer.try_convert(Object.new))     # nil  (no #to_int)
p(Integer.try_convert(NilInt.new))     # nil  (#to_int returns nil)
p(try { Integer.try_convert(BadInt.new) })  # TypeError: can't convert BadInt to Integer (BadInt#to_int gives String)
