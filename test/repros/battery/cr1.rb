obj = Object.new
def obj.create(method_name)
  Proc.new do |&b|
    yield + b.send(method_name)
  end
end
p obj.create(:call) { 7 }.call { 3 }
