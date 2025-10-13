
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
  (let (result high_bits obj sign shift_amt val_to_shift abs_val limb_base limb0 limb1 arr)
    (assign result (add a b))
    (assign shift_amt 29)
    (assign val_to_shift result)
    (assign high_bits (sarl shift_amt val_to_shift))
    (if (or (eq high_bits 0) (eq high_bits -1))
      (return (__int result))
      (do
        (assign obj (callm Integer new))
        (if (lt result 0)
          (assign sign (__int -1))
          (assign sign (__int 1)))

        (assign abs_val result)
        (if (lt abs_val 0)
          (assign abs_val (sub 0 abs_val)))

        (assign limb_base (callm obj __limb_base_raw))
        (assign limb0 (mod abs_val limb_base))
        (assign limb1 (div abs_val limb_base))

        (assign arr (callm Array new))
        (callm arr push ((__int limb0)))
        (if (ne limb1 0)
          (callm arr push ((__int limb1))))

        (callm obj __set_heap_data (arr sign))
        (return obj)))
  )
)
