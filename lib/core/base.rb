
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

# Minimal bignum support - detect overflow and handle it
%s(defun __add_with_overflow (a b)
  (let (result high_bits obj sign shift_amt val_to_shift)
    (assign result (add a b))
    # Check if result fits in 30 bits by shifting right 29
    (assign shift_amt 29)
    (assign val_to_shift result)
    (assign high_bits (sarl shift_amt val_to_shift))
    # If high_bits is 0 or -1, result fits in fixnum
    (if (or (eq high_bits 0) (eq high_bits -1))
      (return (__int result))
      (do
        # Overflow detected - allocate heap integer
        (assign obj (callm Integer new))
        # Determine sign
        (if (lt result 0)
          (assign sign (__int -1))
          (assign sign (__int 1)))
        # Pass tagged value to __set_heap_data which will wrap it in an array
        # Note: Array literal creation moved to __set_heap_data to keep s-expression code simple
        (callm obj __set_heap_data ((__int result) sign))
        (return obj)))
  )
)
