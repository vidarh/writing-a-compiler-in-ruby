# Common missing methods added together: Range#size, Array#max(n)/min(n) (+ block comparator),
# String#delete_prefix/delete_suffix. All print identically under MRI and the compiler.
a = (1..5).size; p a          # 5
b = (1...5).size; p b         # 4
c = (5..1).size; p c          # 0  (empty)
d = ('a'..'e').size; p d      # nil (non-integer)
p [5,3,8,1,9,2].max(3)        # [9, 8, 5]
p [5,3,8,1,9,2].min(3)        # [1, 2, 3]
p [3,1,2].max(5)              # [3, 2, 1] (n > length)
p ["bb","a","ccc"].max(2){|x,y| x.length <=> y.length}  # ["ccc", "bb"]
p "hello".delete_prefix("he") # "llo"
p "hello".delete_suffix("lo") # "hel"
p "hello".delete_prefix("xy") # "hello" (unchanged)
p "abcabc".delete_suffix("abc") # "abc"
