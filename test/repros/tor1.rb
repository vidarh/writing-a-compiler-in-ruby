# String#to_r (lib/core/string.rb): parse a leading rational literal, ignore whitespace and trailing
# junk, return (0/1) when there is no number. Prints identically under MRI and the compiler.
p "1/2".to_r      # (1/2)
p "3".to_r        # (3/1)
p "0.75".to_r     # (3/4)
p "-3/4".to_r     # (-3/4)
p "0.3".to_r      # (3/10)
p "  1/2  ".to_r  # (1/2)
p "foo".to_r      # (0/1)
p "".to_r         # (0/1)
p "22/7".to_r     # (22/7)
p "+7/2".to_r     # (7/2)
