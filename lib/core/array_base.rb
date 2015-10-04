
# The bare minimum of Array, required to be in place before the first
# splat method call
#
class Array
  # __get_fixum should technically be safe to call, but lets not tempt fate
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

    # FIXME: This called __get_fixnum, which means it fails when called
    # from __new_empty. May want to create new method to handle the whol
    # basic nasty splat allocation
    # @capacity = (newlen * 4 / 3) + 4
    %s(assign @capacity (add (div (mul newlen 4) 3) 4))

    %s(if (ne @ptr 0)
         (assign @ptr (realloc @ptr (mul @capacity 4)))
         (assign @ptr (calloc @capacity 4))
         )
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
# This also means that Array#initialize *can not* allocate objects,
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
    (callm splat __grow (max))
    (while (lt pos max)
       (do
          (callm splat __set (pos (index r pos)))
          (assign pos (add pos 1))
          )
        )
  splat
  ))
