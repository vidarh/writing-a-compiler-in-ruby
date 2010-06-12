
class Foo
  @@cvar = "class var"

  def cvar
    @@cvar
  end
end

foo = Foo.new
%s(printf "%s\n" (callm (foo cvar) __get_raw))
