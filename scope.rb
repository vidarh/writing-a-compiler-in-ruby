

class Scope
  attr_reader :next

  def method
    nil
  end

  def add_constant(c)
    @next.add_constant(c) if @next
  end

  def find_constant(c)
    @next.find_constant(c) if @next
  end

  def name
    ""
  end

  def class_scope
    self
  end

  def lvaroffset
    0
  end

  def set_vtable_entry(name,realname,f)
    @next.set_vtable_entry(name,realname,f) if @next
  end

  def vtable
    @next ? @next.vtable : {}
  end

  def break_label
    @next ? @next.break_label : nil
  end

end


require 'globalscope'
require 'funcscope'
require 'sexpscope'
require 'localvarscope'
require 'classcope'
require 'controlscope'
