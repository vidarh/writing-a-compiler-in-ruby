
class Proc
  def call
    %s(call (index self 1))
  end
end

# We can't create a Proc from a raw function directly, so we get
# nasty:
%s(defun __new_proc (addr)
(let (p)
   (assign p (malloc (mul 4 (index Proc 1)))) # index 1 is the instance size
   (assign (index p 0) Proc)
   (assign (index p 1) addr)
   p
))
