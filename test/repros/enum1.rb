# Block-less Array iterators return an Enumerator instead of crashing (each_index/find/find_index/
# sort_by/partition/take_while/drop_while) or returning nil (find_index). With a block, unchanged.
# block-less returns an enumerator (was crash/nil). For non-short-circuiting methods .to_a replays fully;
# for find/find_index only the class is asserted (to_enum replay can't faithfully repeat a short-circuit).
p [1,2,3].each_index.to_a                              # [0, 1, 2]
p [1,2,3].find.class.to_s.include?("numerator")        # true
p [1,2,3].find_index.class.to_s.include?("numerator")  # true
p [3,1,2].sort_by.class.to_s.include?("numerator")     # true
p [1,2,3].partition.class.to_s.include?("numerator")   # true
p [1,2,3,4].take_while.class.to_s.include?("numerator")# true
p [1,2,3].drop_while.class.to_s.include?("numerator")  # true
# WITH a block, behavior is unchanged
p [1,2,3,4].find{|x| x>2}          # 3
p [1,2,3,4].find_index{|x| x>2}    # 2
p [1,2,3,4].find_index(3)          # 2  (value-arg form still works)
p [3,1,2].sort_by{|x| x}           # [1, 2, 3]
p [1,2,3,4].partition{|x| x.even?} # [[2, 4], [1, 3]]
p [1,2,3,4].take_while{|x| x<3}    # [1, 2]
p [1,2,3,4].drop_while{|x| x<3}    # [3, 4]
p [1,2,3].each_index{|i| i}        # [1, 2, 3]  (returns self)
