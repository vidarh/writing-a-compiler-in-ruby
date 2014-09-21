

class Scope
  def method
    nil
  end

  def add_constant(c)
    @next.add_constant(c) if @next
  end

  def find_constant(c)
    @next.find_constant(c) if @next
  end
end


require 'globalscope'
require 'funcscope'
require 'sexpscope'
require 'localvarscope'
require 'classcope'
