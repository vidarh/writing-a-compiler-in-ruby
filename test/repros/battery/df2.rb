def it3; yield; end
it3 do
  def bar
    1
  end
  def foo(bar = bar())
    bar
  end
  p foo
end
