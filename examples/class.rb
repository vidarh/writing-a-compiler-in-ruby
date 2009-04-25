
class Foo

  def bar
    puts("test")
    @foo = "Some text"
    self.hello
  end

  def hello
    printf("Hello World! - %s\n",@foo)
  end
end

%s(let (f) 
  (assign f (callm Foo new))
  (callm f bar)
)
