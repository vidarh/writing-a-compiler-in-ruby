def it3; yield; end
it3 do
  klass = Class.new do
    attr_reader :m
    def initialize; $spec_m = 0; end
    def m=(v); $spec_m = v; 42; end
    def m; $spec_m; end
  end
  obj = klass.new
  obj&.m += 3
  p obj.m
end
