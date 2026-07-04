m = Module.new do
  def self.const_added(name)
    p name
  end
end
p "done"
