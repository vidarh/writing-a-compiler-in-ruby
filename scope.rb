
class Scope
  attr_reader :next

  def initialize n=nil
    @next = n
  end

  def method
    @next.method if @next
  end

  def  get_arg(a, save = false)
    @next ? @next.get_arg(a, save) : nil
  end

  def add_global(c)
    @next.add_global(c) if @next
  end

  def add_constant(c)
    @next.add_constant(c) if @next
  end

  def find_constant(c)
    @next ? @next.find_constant(c) : nil
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

  def loop_label
    @next ? @next.loop_label : nil
  end

    # Defer to parents class variable.
  # FIXME: This might need to actually dynamically
  # look up the superclass?
  def get_class_var(var)
    @next.get_class_var(var)
  end

end


require 'globalscope'
require 'funcscope'
require 'sexpscope'
require 'localvarscope'
require 'classcope'
require 'controlscope'
