
def __new_class_object(size)
  ob = malloc(size)
  %s(assign (index ob 0) Class)
  ob
end

class Class
  def new
    ob = malloc(4)
    %s(assign (index ob 0) self)
    ob
  end
end

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
