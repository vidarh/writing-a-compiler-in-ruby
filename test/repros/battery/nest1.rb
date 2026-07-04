def outer
  pc = Object.new
  def pc.create(mn)
    Proc.new do |&b|
      yield + b.send(mn)
    end
  end
  a = pc.create(:call) { 7 }
  a.call { 3 }
end
p outer
