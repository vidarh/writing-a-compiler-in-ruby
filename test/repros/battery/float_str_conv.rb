# String#to_f (lenient strtod) and Kernel#Float (strict). Guards the C-call path (__str_to_f /
# __float_strict) + the raise paths against crashes. Before this, String#to_f didn't exist and
# Float() didn't exist. Values verified against MRI separately.
puts "3.14".to_f.to_s         # 3.14
puts "  .5xyz".to_f.to_s      # 0.5   (lenient: leading parse, trailing junk ignored)
puts "abc".to_f.to_s          # 0.0
puts "-2.5e2".to_f.to_s       # -250.0
puts Float("42").to_s         # 42.0
puts Float("  2.5  ").to_s    # 2.5   (surrounding whitespace ok)
puts Float(7).to_s            # 7.0   (Integer)
begin; Float("bad"); puts "NO"; rescue ArgumentError; puts "AE"; end   # AE
begin; Float("1.2.3"); puts "NO"; rescue ArgumentError; puts "AE"; end  # AE
begin; Float(nil); puts "NO"; rescue TypeError; puts "TE"; end          # TE
