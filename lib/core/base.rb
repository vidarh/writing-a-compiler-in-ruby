
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

# Initialize the garbage collector
#%s(tgc_start (stackframe) __roots_start __roots_end)

%s(defun __alloc (size opt)
  (let (ptr)
    (assign ptr (calloc size 1))
    (if (eq ptr 0) (return 0))
    (return ptr)
  )
)

%s(defun __alloc_mem (size)  (return (__alloc size 0)))
%s(defun __alloc_leaf (size) (return (__alloc size 1)))
%s(defun __realloc (ptr size) (realloc ptr size))

# FIXME: 32-bit assumption
%s(defun __array (size)      (__alloc_mem  (mul size 4)))
%s(defun __array_leaf (size) (__alloc_leaf (mul size 4)))

%s(defun __alloc_env (size)  (do
  (__array size)
))

# We'll use this for various instrumentation
%s(assign __cnt 0)
%s(defun __docnt () (do
  (assign __cnt (add __cnt 1))
  (if (eq (mod __cnt 1000) 0)
    (dprintf 2 "__cnt: %ld\n" __cnt)
  )
))

#%s(atexit tgc_stop)

# Create a heap-allocated integer - for now just returns wrapped value
# TODO: Actually allocate Integer object with @limbs and @sign
%s(defun __make_heap_integer (value sign)
  (do
    (dprintf 2 "HEAP_INTEGER\n")
    # FIXME: Should use (callm Integer new) but that requires
    # Integer class to be defined first
    # For now, return wrapped value (incorrect but safe)
    (return (__int value)))
)

# Minimal bignum support - detect overflow and handle it
%s(defun __add_with_overflow (a b)
  (let (result high_bits sign)
    (assign result (add a b))
    # Check if result fits in 30 bits by shifting right 29
    (assign high_bits (sarl 29 result))
    # If high_bits is 0 or -1, result fits in fixnum
    (if (or (eq high_bits 0) (eq high_bits -1))
      (return (__int result))
      (do
        # Overflow detected - need heap integer
        # Determine sign: negative if high bit is set
        (assign sign (if (lt result 0) -1 1))
        (return (__make_heap_integer result sign))))
  )
)
