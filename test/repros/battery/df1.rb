def it3; yield; end
it3 do
  def foo; "bar"; end
  foo = "foo"
  p foo()
  p foo
end
