
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

# The garbage collector is started from compile_main (compiler.rb) BEFORE any allocation -- it must run
# before the first tgc_add. It cannot live here: this file's top-level runs after the user program's
# top-level, so a top-level closure's env would be allocated (and the GC used) before this line.
#%s(tgc_start (stackframe) __roots_start __roots_end)

%s(defun __alloc (size opt)
  (let (ptr)
    # tgc_alloc bump-allocates size bytes (zeroed) from a GC arena and returns the object (0 on OOM).
    # This replaces the old calloc + tgc_add (per-object hashtable insert) path.
    (assign ptr (tgc_alloc size opt))
    # Diagnostic probe (purely additive; still returns 0 as before): on a 32-bit target the
    # per-process address space is ~3-4GB regardless of system RAM, so a heavy/runaway-allocating
    # spec can exhaust it and tgc_alloc returns NULL. Callers that don't check the 0 then wild-write
    # near address 0 -> SIGSEGV. Emitting the size here means any such event shows up verbatim in the
    # sweep's captured spec output. Guard on fd 2 only; dprintf uses a static buffer and needs no heap.
    (if (eq ptr 0) (do
      (dprintf 2 "__alloc: FATAL tgc_alloc failed for %ld bytes (32-bit address space exhausted?)\n" size)
      (return 0)
    ))
    (return ptr)
  )
)

%s(defun __alloc_mem (size)  (return (__alloc size 0)))
%s(defun __alloc_leaf (size) (return (__alloc size 1)))
%s(defun __realloc (ptr size) (tgc_realloc ptr size))

# FIXME: 32-bit assumption
# Call __alloc directly instead of routing through __alloc_mem/__alloc_leaf/__array: these are among the
# HOTTEST functions (~167M allocs per self-compile) and the wrappers are NOT inlined, so each level was a
# real call/prologue/ret. __alloc keeps the single OOM diagnostic. Arrays/objects: 3 calls -> 2; envs
# (__alloc_env): 4 calls -> 2. Pure call-count reduction, identical behaviour.
%s(defun __array (size)      (__alloc (mul size 4) 0))
%s(defun __array_leaf (size) (__alloc (mul size 4) 1))

%s(defun __alloc_env (size)  (__alloc (mul size 4) 0))

# We'll use this for various instrumentation
%s(assign __cnt 0)
%s(defun __docnt () (do
  (assign __cnt (add __cnt 1))
  (if (eq (mod __cnt 1000) 0)
    (dprintf 2 "__cnt: %ld\n" __cnt)
  )
))

%s(atexit tgc_stop)

# Minimal bignum support - detect overflow and handle it
%s(defun __add_with_overflow (a b)
  (let (result high_bits obj sign shift_amt val_to_shift abs_val limb_base limb0 limb1 arr)
    (assign result (add a b))
    (assign shift_amt 30)
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
