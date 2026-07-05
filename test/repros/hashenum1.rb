# Hash gains pair-oriented Enumerable methods (Hash cannot include Enumerable here): sort, first,
# take, drop, find/detect, group_by, partition. Array gains entries (=to_a) and minmax_by.
h = {a:3, b:1, c:2}
p h.sort                          # [[:a, 3], [:b, 1], [:c, 2]]
p h.first                         # [:a, 3]
p h.first(2)                      # [[:a, 3], [:b, 1]]
p h.take(2)                       # [[:a, 3], [:b, 1]]
p h.drop(1)                       # [[:b, 1], [:c, 2]]
p h.find{|k,v| v==2}              # [:c, 2]
p h.detect{|k,v| v==1}            # [:b, 1]
p h.group_by{|k,v| v.odd?}        # {true=>[[:a, 3], [:b, 1]], false=>[[:c, 2]]}
p h.partition{|k,v| v>1}          # [[[:a, 3], [:c, 2]], [[:b, 1]]]
p h.map{|k,v| v}                  # [3, 1, 2]
p h.collect{|k,v| k}              # [:a, :b, :c]  (was a no-op Enumerator; hash_ext bug fixed)
p h.each_with_object([]){|(k,v),acc| acc << k}  # [:a, :b, :c]
p h.inject(0){|s,(k,v)| s+v}      # 6
p h.reduce(:+)                    # [:a, 3, :b, 1, :c, 2]
p h.tally                         # {[:a, 3]=>1, [:b, 1]=>1, [:c, 2]=>1}
p [1,2,3].entries                 # [1, 2, 3]
p [[1,3],[2,1],[3,2]].minmax_by{|x| x[1]}  # [[2, 1], [1, 3]]
