# Array#grep/grep_v (=== matching, optional map block), plus block-less detect/each_entry returning an
# Enumerator (Array cannot include Enumerable in this runtime, so these are defined directly on Array).
p [1,"x",2,"y",3].grep(Integer)          # [1, 2, 3]
p [1,"x",2,"y",3].grep(String)           # ["x", "y"]
p [1,2,3,4,5].grep(2..4)                 # [2, 3, 4]
p ["cat","dog","cow"].grep(/c/)          # ["cat", "cow"]
p [1,2,3].grep(Integer){|x| x*10}        # [10, 20, 30]
p [1,"x",2].grep_v(Integer)              # ["x"]
p [1,2,3,4].detect{|x| x>2}              # 3
p [1,2,3].detect.class.to_s.include?("numerator")     # true  (block-less -> Enumerator)
p [1,2,3].each_entry.to_a                # [1, 2, 3]
p [1,2,3].each_entry{|x| x}              # [1, 2, 3]  (returns self)
