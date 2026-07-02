module M
  class A
    def m1; 1; end
    def m2; 2; end
    def m3; 3; end
    def m4; 4; end
    def m5; 5; end
  end
  S = Struct.new(:value) do
    def to_int; value; end
  end
end
[1].each { Object.new }
STDERR.puts "SURVIVED"
