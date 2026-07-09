# Marshal must raise TypeError for anonymous classes/modules (MRI parity), and round-trip a named
# class reference ('c') back to the same class object.
begin; Marshal.dump(Class.new.new); puts "FAIL: obj-anon no raise"; rescue TypeError; puts "ok obj-anon"; end
begin; Marshal.dump(Class.new);     puts "FAIL: cls-anon no raise"; rescue TypeError; puts "ok cls-anon"; end
begin; Marshal.dump(Module.new);    puts "FAIL: mod-anon no raise"; rescue TypeError; puts "ok mod-anon"; end

class MarshalAnonPoint; def initialize; @x = 1; end; end
o = Marshal.load(Marshal.dump(MarshalAnonPoint.new))
puts(o.instance_variable_get(:@x) == 1 ? "ok named-obj" : "FAIL named-obj")
puts(Marshal.load(Marshal.dump(MarshalAnonPoint)) == MarshalAnonPoint ? "ok class-ref" : "FAIL class-ref")
