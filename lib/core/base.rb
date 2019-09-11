
#
# Low level parts of the runtime support.
#
# Anything that goes here can not rely on anything
# resembling Ruby to actually work (e.g. no String,
# Fixnum, Symbol, Class, Object...) so should almost
# certainly use the s-exp syntax.
#
#
%s(defun __method_missing (sym ob (args rest)) 
   (let (cname)
    (assign cname (callm (index ob 0) inspect))
    (printf "Method missing: %s#%s\n"
      (callm (callm cname to_s) __get_raw) 
      (callm (callm sym to_s) __get_raw))
    (div 0 0)
    0)
)

%s(defun __array (size) (malloc (mul size 4)))
%s(defun __alloc_mem (size) (calloc size 4))
