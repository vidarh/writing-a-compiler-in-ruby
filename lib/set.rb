
#
# FIXME
# This is an awful, quick and dirty stub of a Set implementation
# to get some of the basics in place
#
class Set
  def initialize
    @set = Hash.new # Told you it was dirty
  end

  def << k
    @set[k]=1
  end

  def to_a
    @set.keys
  end

  def self.[] *args
    s = Set.new
    args.each do |a|
      s << a
    end
    s
  end
end
