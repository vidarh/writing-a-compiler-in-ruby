def it3; yield; end
it3 do
  obj = Object.new
  class << obj
    def a_sm; 42; end
  end
  p obj.a_sm
end
