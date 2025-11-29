
# In MRI Symbol objects are "type tagged" integers. That is, they are not
# real objects at all, rather each symbol is represented by a specific
# 32 bit value, and those values can be identified as symbols by looking
# for a specific bit-pattern in the least significant byte.
#
# This has the advantage of saving space - no actual instances need to be
# constructed. In this instance, however, it creates a lot of complication,
# by requiring the type tags to be checked on each and every method call.
#
# For this reason we will, at least for now, avoid it.
#
# Instead we will keep a hash table of allocated symbols, which we will
# use to return the same object for the same symbol literal

class Symbol

  # FIXME: This is a workaround for a problem with handling
  # instance variables for a class (instance variable would make
  # more sense here.
  @@symbols = {}

  # FIXME: Should be private, but we don't support that yet
  def initialize(name)
    @name = name
    @hash = name.hash
  end

  def intern
    self
  end

  def dup
    self
  end

  def eql? other
    self.==(other)
  end

  def <=> other
    if other.is_a?(Symbol)
      return to_s <=> other.to_s
    else
      nil
    end
  end

  def to_s
    @name
  end

  # NOTE: Alias and frozen? removed - triggers selftest-c crash (Issue #8)
  # TODO: Re-add when vtable size issue is fixed
  # alias id2name to_s

  def to_sym
    self
  end

  # NOTE: frozen? removed - triggers selftest-c crash (Issue #8)
  # def frozen?
  #   true
  # end

  def inspect
    # FIXME: This is incomplete.
    # Ruby is massively annoying here - what gets printed without quotes depend
    # on what is parseable without quotes. For now I'm adding the rules needed
    # to get identical output when parsing the compiler itself. But because of
    # how we create symbols, it'd probably be "cheaper" to just define a flag and
    # "pre-create" these symbols at compile time, since we'll be including either
    # the strings or the code to detect them anyway, and now we're paying the cost
    # on every Symbol#inspect

    return ":==" if @name == "=="
    return ":===" if @name == "==="
    return ":!=" if @name == "!="
    return ":<=" if @name == "<="
    return ":<=>" if @name == "<=>"
    return ":>=" if @name == ">="
    return ":>" if @name == ">"
    return ":<" if @name == "<"
    return ":<<" if @name == "<<"
    return ":>>" if @name == ">>"
    return ":-" if @name == "-"
    return ":/" if @name == "/"
    return ":%" if @name == "%"
    return ":$:" if @name == "$:"

    # FIXME Please tell me this is a bug (but MRI does this, and more)
    return "::<=" if @name == ":<="
    return "::>=" if @name == ":>="
    return ":::>=" if @name == "::>="
    return ":::[]=" if @name == :"::[]="

    o = @name[0].ord
    if (o >= 97 && o <= 122) ||
       (o >= 64 && o <= 91)  ||
       o == 42 || o == 43 || o == 95 || o == 33
      ":#{to_s}"
    else
      ":#{to_s.inspect}"
    end
  end

  def hash
    @hash
  end

  def [] i
    to_s[i]
  end

  # FIXME
  # The compiler should turn ":foo" into Symbol.__get_symbol("foo").
  # Alternatively, the compiler can do this _once_ at the start for
  # any symbol encountered in the source text, and store the result.
  def self.__get_symbol(name)
    sym = @@symbols[name]
    if !sym
      sym = Symbol.new(name)
      @@symbols[name] = sym
    end
    sym
  end
end

%s(defun __get_symbol (name) (callm Symbol __get_symbol ((__get_string name))))

%s(__compiler_internal symbol_list)
