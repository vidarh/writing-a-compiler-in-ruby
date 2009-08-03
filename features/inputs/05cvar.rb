
class Foo
  @@cvar = "class var"

  def cvar
    @@cvar
  end
end

foo = Foo.new
printf "%s\n",foo
