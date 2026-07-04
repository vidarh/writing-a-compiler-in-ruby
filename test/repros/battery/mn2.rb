m = Module.new do
  def self.const_added(name)
    p name
  end
  module self::A
    def self.const_added(name)
      p name
    end
    module self::B
    end
  end
end
p "done"
