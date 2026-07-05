# Guards String.allocate: the binary-safe String keeps its byte length in @length and bytes in @buffer,
# which the generic Class#allocate leaves unset, so #size/#<< on the result read garbage and segfaulted
# (core/string/allocate_spec). String.allocate must return a usable empty string.
s = String.allocate
p s.class      # String
p s.size       # 0
p s.empty?     # true
s << "more"
p s            # "more"
p (s == "more") # true
s << "!"
p s.length     # 5
