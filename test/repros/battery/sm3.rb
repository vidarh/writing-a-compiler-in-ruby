module BasicObjectSpecs
  class SingletonMethod
    def self.singleton_method_added(name)
      $rec = [:singleton_method_added, name]
    end
    def self.singleton_method_to_alias; 1; end
  end
end
# alias_method in singleton
class BasicObjectSpecs::SingletonMethod
  class << self
    alias_method :m1, :singleton_method_to_alias
  end
end
# alias in singleton
class BasicObjectSpecs::SingletonMethod
  class << self
    alias m2 singleton_method_to_alias
  end
end
# define_method in singleton
class BasicObjectSpecs::SingletonMethod
  class << self
    define_method :m3 do; end
  end
end
p $rec
