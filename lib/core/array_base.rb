
# The bare minimum of Array, required to be in place before the first
# splat method call
#
class Array
  # __int should technically be safe to call, but lets not tempt fate
  # NOTE: The order of these is important, as it is relied on elsewhere
  def __initialize
    %s(assign @len 0)
    %s(assign @ptr 0)
    %s(assign @capacity 0)
  end

  #FIXME: Private; Used by splat handling
  def __len
    @len
  end

  def __ptr
    @ptr
  end

  def __grow newlen
    # FIXME: This is just a guestimate of a reasonable rule for
    # growing. Too rapid growth and it wastes memory; to slow and
    # it is, well, slow to append to.

    # Fresh buffers come from calloc (zeroed), but __realloc is plain realloc: the extension
    # holds GARBAGE. The zeroed-buffer invariant is load-bearing -- __index_set documents that
    # a growing `a[i] = v` leaves the gap reading as nil (element reads map raw 0 to nil), so
    # garbage there gets dispatched on by #== / #inspect -> SIGSEGV (array/fill_spec died
    # printing `[1,2,3,4,5].fill(8, 2){...}`: realloc left slots 5..7 unzeroed). Zero the
    # extension explicitly, tracking the old capacity.
    %s(let (oldcap)
        (assign oldcap @capacity)
        (assign @capacity (add (div (mul newlen 4) 3) 4))
        (if (ne @ptr 0)
          (do
            (assign @ptr (__realloc @ptr (mul @capacity 4)))
            (while (lt oldcap @capacity)
              (do
                (assign (index @ptr oldcap) 0)
                (assign oldcap (add oldcap 1)))))
          (assign @ptr (__array @capacity))))
  end

  #FIXME: Private.
  def __set(idx, obj)
    %s(if (ge idx @len) (assign @len (add idx 1)))
    %s(assign (index @ptr idx) obj)
  end

  def to_a
    self
  end
end


#
# This is necessary because we need to be able to create an Array
# for the splat handling, and since Class.new needs to handle variable
# arguments, we *can not* allocate additional objects, because if we
# do, we'll end up with endless recursion. Which means we *can not*
# call Array.new in the splat handling, since that's actually
# Class.new.
#
# This also means that `Array#initialize` *can not* allocate objects,
# which may be / is a complication, as it means it can not even assign
# integers. At the moment I've partially untangled this by changing
# Array#initialize to use %s(...), but while that may be more efficient,
# it ties us into using s-expressions all over the place in the
# implementation of Array, which I'm not pleased with.
#
%s(defun __splat_to_Array (r na)
   (let (splat pos data max)
    (assign splat (callm Array __new))
    (assign pos 0)
    (assign max (sub na 2))
    (if (gt max 0) (do
      (callm splat __grow (max))
      (while (lt pos max)
         (do
           (callm splat __set (pos (index r pos)))
           (assign pos (add pos 1))
         )
       )
    ))
    splat
  ))
