
class Foo

  def bar
    puts("test")
    self.hello
  end

  def hello
    puts("Hello World!")
  end
end

%s(let (f) 
  (assign f (callm Foo new))
  (callm f bar)
)
