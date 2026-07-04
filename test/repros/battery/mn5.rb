m = Module.new do
  module self::A
    def self.const_added(name)
      p name
    end
  end
end
p "done"
