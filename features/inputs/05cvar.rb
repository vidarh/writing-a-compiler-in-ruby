
class Foo
  @@cvar = "class var"

  def cvar
    @@cvar
  end
end

foo = Foo.new
puts foo.cvar

