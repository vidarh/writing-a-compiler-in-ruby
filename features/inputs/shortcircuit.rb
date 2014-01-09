
def foo
  puts "foo"
  false
end

def bar
  puts "bar"
end

self.foo && bar
