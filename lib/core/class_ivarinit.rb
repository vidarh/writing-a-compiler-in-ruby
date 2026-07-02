#
# Once "nil" is defined, we override __alloc
# to ensure instance variables are automatically
# initialized to nil
#
class Class

  # Raised when allocate is called on a class whose metadata was never initialised -- e.g.
  # `Class.allocate.new`. `Class.allocate` builds a bare class object and nils EVERY slot (it can't tell
  # class-metadata slots from ordinary ivars), so the new class's @instance_size (slot 1) ends up nil
  # rather than a raw size. A later `.new` would `__array(nil)` -> a wild allocation whose slot-0 write
  # segfaults. MRI raises here (core/class/allocate_spec). Kept separate so the guard in allocate is one
  # s-expr branch. Dispatch works because the broken class's own class pointer (slot 0) is still Class,
  # so `self.__allocate_undefined` / `raise` resolve through Class's vtable, not the nil'd slots.
  def __allocate_undefined
    raise TypeError.new("allocator undefined for uninitialized class")
  end

  def allocate
    %s(assign is @instance_size)
    # A real class's @instance_size is a raw int; a class built by Class.allocate has every metadata slot
    # nil'd, so its @instance_size reads back as nil. Allocating with a nil size wild-allocates and
    # segfaults on first use, so raise instead (matches MRI's uninitialised-class behaviour).
    %s(if (eq is nil) (callm self __allocate_undefined))
    %s(assign ob (__array @instance_size))
    %s(assign i 1)
    %s(while (lt i is)
         (do
            (assign (index ob i) nil)
            (assign i (add i 1))
            )
          )
    %s(assign (index ob 0) self)
    ob
  end

end
