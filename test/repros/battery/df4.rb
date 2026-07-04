def bar; 1; end
def foo(bar = bar); bar; end
p foo
p foo(5)
