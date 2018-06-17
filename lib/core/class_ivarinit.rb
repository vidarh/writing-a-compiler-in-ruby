#
# Once "nil" is defined, we override __alloc
# to ensure instance variables are automatically
# initialized to nil
#
class Class

  def allocate
    %s(assign is @instance_size)
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
