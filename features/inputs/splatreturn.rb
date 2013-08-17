
def foo(a)
  "Hey!"
end

def splat *args
  foo(*args)
end

puts(splat(1))

