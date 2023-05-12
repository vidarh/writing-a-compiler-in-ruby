
#
# We re-open class here, after Hash and Symbol has ben initialized, to add the 
# method -> vtable offset mapping.
#

class Class
  @method_to_voff = {}

  def self.method_to_voff
    @method_to_voff
  end

  def method_missing sym, *args
      %s(if sym (printf "WARNING:    Method: '%s'\n" (callm (callm sym to_s) __get_raw)))
      %s(printf "WARNING:    symbol address = %p\n" sym)
      %s(printf "WARNING:    class '%s'\n" (callm (callm self name) __get_raw))
      %s(call exit 1)
  end

  # This is called by __send__
  def __send_for_obj__ obj,sym,*args
    sym  = sym.to_sym
    voff = Class.method_to_voff[sym]
    if !voff
      # FIXME: This needs to change once we handle "define_method"
      return obj.method_missing(sym, *args)
    else
      # We can't inline this in the call, as our updated callm
      # doesn't allow method/function calls in the method slot
      # for simplicity, for now anyway.
      %s(assign raw (callm voff __get_raw))
      %s(callm obj (index self raw) ((splat args)))
    end
  end

  def ===(o)
    o.is_a?(self)
  end

  # FIXME: Belongs in Kernel
end

%s(sexp
(defun __printerr (format a1 a2 a3) (do
   (printf format a1 a2 a3)
   (div 1 0)
))

(defun __minarg (name minargs actual) (do
  (__printerr "ArgumentError: In %s - expected a minimum of %d arguments, got %d\n"
          name minargs (sub actual 2))
))


(defun __maxarg (name maxargs actual) (do
  (__printerr "ArgumentError: In %s - expected a maximum of %d arguments, got %d\n"
          name maxargs (sub actual 2))
))

 (defun __eqarg (name eqargs actual) (do
  (__printerr "ArgumentError: In %s - expected exactly %d arguments, got %d\n"
          name eqargs (sub actual 2))
))

)

#
# Populate the Class.method_to_voff hash based on the __vtable_names
# table that gets generated by the compiler.
#
%s(let (i max ptr)
   (assign i 0)
   (assign max __vtable_size)
   (assign h (callm Class method_to_voff))
   (while (lt i max) 
      (do
        (assign ptr (index __vtable_names i))
        (if (ne ptr 0)
          (callm h []= ((__get_symbol ptr) (__int i)))
        )
        (assign i (add i 1))
      )
    )
  )
