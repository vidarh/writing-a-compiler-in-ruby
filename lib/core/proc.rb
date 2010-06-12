
class Proc
  # FIXME: Add support for handling arguments (and blocks...)
  def call
    %s(call (index self 1) (self 0 (index self 2)))
  end
end

# We can't create a Proc from a raw function directly, so we get
# nasty. The advantage of this rather ugly method is that we
# don't in any way expose a constructor that takes raw functions
# to normal Ruby
#
%s(defun __new_proc (addr env)
(let (p)
 # Assuming 3 pointers for the instance size. Need a better way for this
   (assign p (malloc 12))
   (assign (index p 0) Proc)
   (assign (index p 1) addr)
   (assign (index p 2) env)
   p
))
