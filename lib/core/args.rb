
%s(sexp (assign __D_0 (__get_string (index __argv 0))))

ARGV=[]
%s(let (__src __i)
  (assign __i 1)
  (callm ARGV __grow ((sub __argc 1)))
  (while (lt __i __argc) (do
    (callm ARGV __set ((sub __i 1) (__get_string (index __argv __i))))
    (assign __i (add __i 1))
  ))
)
