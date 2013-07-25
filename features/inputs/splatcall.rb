
class Foo
  def foo arg1,arg2
    %s(printf "foo: %d\n" numargs)
    %s(printf "%p\n" arg1)
    %s(printf "%p\n" arg2)
  end

  def bar *splat
    %s(printf "bar: %d\n" numargs)
    %s(printf "%p\n" (index splat 0))
    %s(printf "%p\n" (index splat 1))
    foo(*splat)
  end
end

f = Foo.new
a = "foo"
b = "bar"

# Should give same pairs of output 3 times
f.foo(a,b)
f.bar(a,b)




