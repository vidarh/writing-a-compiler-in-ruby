def stackfence_x
  yield
end
def callm_args_x(a)
  yield
end
def outer(scope, ob, args, dls = false)
  stackfence_x do
    r = nil
    callm_args_x(args) do
      if dls && dls != :runtime
        r = dls.to_sym
      else
        r = :other
      end
    end
    r
  end
end
p outer(1, 2, [3], :Object)
p outer(1, 2, [3])
puts "done"
