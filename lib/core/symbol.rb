
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

  # Symbols cannot have a singleton class in Ruby -- raise TypeError (core/kernel/singleton_class_spec).
  def singleton_class
    raise TypeError.new("can't define singleton")
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

  alias id2name to_s

  def to_sym
    self
  end

  # Length of the symbol's name. Matches MRI (Symbol#size / #length); the compiler itself relies on this
  # (compile_exp guards with `exp.size == 0`, which reaches a bare symbol for a `**kw`-forwarded hash).
  def size
    @name.size
  end

  alias length size

  def frozen?
    true
  end

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

  # NOTE: Symbol#[] deliberately mirrors this runtime's String#[] (single Integer
  # index -> byte CODE), NOT MRI (which returns a 1-char String). The COMPILER
  # SOURCE relies on the byte behavior somewhere in its name-mangling paths:
  # making this return Strings corrupted the self-compiled compiler's emitted
  # global labels (garbage bss names -> assembly failure). Migrate the compiler
  # to .to_s[...] before making this MRI-correct. Symbol#slice below IS
  # MRI-correct (returns Strings) and is what the specs mostly exercise.
  def [](*args)
    to_s[*args]
  end

  # MRI-shaped element access: returns Strings (or nil), every form.
  def slice(*args)
    s = to_s
    if args.length == 1 && args[0].is_a?(Integer)
      c = s[args[0]]
      return nil if c.nil?
      return c.chr
    end
    s[*args]
  end

  def match(pattern, pos = 0)
    to_s.match(pattern, pos)
  end

  def match?(pattern, pos = 0)
    to_s.match?(pattern, pos)
  end

  def =~(pattern)
    to_s =~ pattern
  end

  def casecmp(other)
    return nil if !other.is_a?(Symbol)
    to_s.casecmp(other.to_s)
  end

  def casecmp?(other)
    return nil if !other.is_a?(Symbol)
    to_s.casecmp?(other.to_s)
  end

  # Case/length operations mirror the String ones (returning a Symbol for the case methods).
  def upcase
    to_s.upcase.to_sym
  end

  def downcase
    to_s.downcase.to_sym
  end

  def capitalize
    to_s.capitalize.to_sym
  end

  def swapcase
    to_s.swapcase.to_sym
  end

  def length
    to_s.length
  end
  alias size length

  def empty?
    to_s.length == 0
  end

  def succ
    to_s.succ.to_sym
  end
  alias next succ

  def start_with?(*prefixes)
    to_s.start_with?(*prefixes)
  end

  def end_with?(*suffixes)
    to_s.end_with?(*suffixes)
  end

  # Returns a Proc that calls the method named by self on its first argument
  # Used for: array.map(&:to_s) which becomes array.map(&:to_s.to_proc)
  def to_proc
    method_name = @name
    # NB: a splat block param (|obj, *args|) currently segfaults when the proc is called, so handle the
    # common arities explicitly instead. One arg covers map/each/select(&:sym); the optional second covers
    # inject/reduce(&:+) where the proc is called with (memo, item).
    Proc.new { |obj, other| other.nil? ? obj.__send__(method_name) : obj.__send__(method_name, other) }
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

# Intern frozen string literals (`# frozen_string_literal: true` files) here, right after symbols: classes
# exist by this point in startup, so __get_frozen_string can allocate. Injects __FSL_n = __get_frozen_string
# (<content>) for each unique frozen literal; see Compiler#output_frozen_string_list.
%s(__compiler_internal frozen_string_list)
