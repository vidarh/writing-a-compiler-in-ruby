
require 'delegate'

# Used to hold a possiby-typed value
# Currently, valid values for "type"
# are :object or nil.
class Value < SimpleDelegator
  attr_reader :type

  def initialize ob, type = nil
    super(ob)
    @type = type
  end

  # Evil. Since we explicitly check for Symbol some places
  def is_a?(ob)
    __getobj__.is_a?(ob)
  end
end


