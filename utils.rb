
# Visit all objects in an array recursively.
# yield any object that #is_a?(c)
def deep_collect node, c = Array, &block
  ret = []
  if node.is_a?(c)
    ret << yield(node)
  end
  if node.is_a?(Array)
    node.each do |n| 
      if n.is_a?(Array) || n.is_a?(c)
        ret << deep_collect(n,c,&block) 
      end
    end
  end
  ret.flatten.uniq.compact
end

