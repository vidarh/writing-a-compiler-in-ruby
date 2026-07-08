# Minimal Random: a deterministic seeded LCG (glibc constants). Enough to stop "uninitialized constant
# Random" crashes and to make same-seed sequences reproducible (so equal_value / seeded-bytes specs can
# pass). #rand with no argument should return a Float in [0,1), but Float is stubbed here, so the no-arg
# form returns a raw integer (those specs FAIL rather than crash). Self-contained -> safe to add (cf. Set).
class Random
  LCG_A = 1103515245
  LCG_C = 12345
  LCG_M = 2147483648  # 2**31

  def initialize(seed = 0)
    @seed = seed
    @state = seed & (LCG_M - 1)
  end

  def seed
    @seed
  end

  # Advance the generator and return the next 31-bit value.
  def _next
    @state = ((@state * LCG_A) + LCG_C) & (LCG_M - 1)
    @state
  end

  # No argument -> a Float in [0, 1). An Integer limit -> an Integer in [0, limit). A Float limit ->
  # a Float in [0, limit). (_next yields a 31-bit value, so dividing by LCG_M lands in [0, 1).)
  def rand(limit = nil)
    if limit.nil?
      _next.to_f / LCG_M.to_f
    elsif limit.is_a?(Float)
      (_next.to_f / LCG_M.to_f) * limit
    else
      _next % limit
    end
  end

  def bytes(n)
    s = ""
    i = 0
    while i < n
      s = s + (_next & 255).chr
      i = i + 1
    end
    s
  end

  def ==(other)
    other.is_a?(Random) && other.seed == @seed
  end

  DEFAULT = Random.new(1)

  def self.rand(limit = nil)
    DEFAULT.rand(limit)
  end

  def self.srand(number = 0)
    DEFAULT.seed
  end

  def self.new_seed
    0
  end

  def self.bytes(n)
    DEFAULT.bytes(n)
  end

  # Not real OS entropy; deterministic filler so urandom specs run rather than crash.
  def self.urandom(n)
    DEFAULT.bytes(n)
  end
end
