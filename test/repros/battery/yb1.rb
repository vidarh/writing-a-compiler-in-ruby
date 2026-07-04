obj = Object.new
def obj.create
  Proc.new do |&b|
    "yield=" + yield.to_s + " b=" + (b ? b.call.to_s : "nil")
  end
end
p obj.create { "M" }.call { "C" }
