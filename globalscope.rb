
# Holds globals, and (for now at least), global constants.
# Note that Ruby-like "constants" aren't really - they are "assign-once"
# variables. As such, some of them can be treated as true constants
# (because their value is known at compile time), but some of them are
# not. For now, we'll treat all of them as global variables.
class GlobalScope < Scope
  attr_reader :class_scope, :globals
  attr_accessor :aliases

  def initialize(offsets)
    @vtableoffsets = offsets
    @globals = {}
    @class_scope = ClassScope.new(self,"Object",@vtableoffsets,nil)

    # Despite not following "$name" syntax, these are really global constants.
    @globals[:false] = true
    @globals[:true]  = true
    @globals[:nil]   = true

    # Special "built-in" globals with single-character or special names starting with $
    # Map them to assembly-safe names. Some use Ruby standard aliases, others use
    # compiler-specific descriptive names prefixed with __.
    @aliases = {
      :"$:" => "LOAD_PATH",           # Load path array
      :"$\"" => "LOADED_FEATURES",     # Array of loaded files (loaded by require)
      :"$0" => "__D_0",                # Program name
      :"$!" => "__exception_message",  # Last exception message (set by raise)
      :"$@" => "__exception_backtrace",# Last exception backtrace
      :"$?" => "__child_status",       # Status of last executed child process
      :"$/" => "__input_record_separator",  # Input record separator (default: "\n")
      :"$\\" => "__output_record_separator", # Output record separator
      :"$," => "__output_field_separator",   # Output field separator for print/puts
      :"$;" => "__field_separator",    # Default separator for String#split
      :"$." => "__input_line_number",  # Current input line number
      :"$&" => "__last_match",         # String matched by last successful regex
      :"$$" => "__process_id",         # Process ID of current Ruby process
      :"$=" => "__case_insensitive",   # Case-insensitive comparison (deprecated, now no-op)
      :"$<" => "__argf",               # ARGF - virtual concatenation of files from command line
      :"$>" => "__default_output",     # Default output destination (STDOUT by default)
      :"$~" => "__last_match_data",    # MatchData object from last regex match
      :"$`" => "__pre_match",          # String before the match
      :"$'" => "__post_match",         # String after the match
      :"$+" => "__last_paren_match",   # Last captured group from regex match
      :"$*" => "__argv",               # Command-line arguments (ARGV)
      # $-x command-line option flags
      :"$-0" => "__D_dash_0",          # Input record separator alias ($/)
      :"$-a" => "__D_dash_a",          # Autosplit mode
      :"$-d" => "__D_dash_d",          # Debug mode
      :"$-F" => "__D_dash_F",          # Autosplit field separator
      :"$-i" => "__D_dash_i",          # In-place edit mode
      :"$-I" => "__D_dash_I",          # Load path directories
      :"$-K" => "__D_dash_K",          # Character encoding
      :"$-l" => "__D_dash_l",          # Line-ending processing
      :"$-p" => "__D_dash_p",          # Print loop mode
      :"$-v" => "__D_dash_v",          # Verbose mode
      :"$-w" => "__D_dash_w"           # Warning level
    }
  end

  def add_global(c)
    @globals[c] = true
  end

  def add_global_alias(new_name, old_name)
    # Get the storage name for the old global (resolving aliases)
    s = @aliases[old_name]
    # If old_name is already an alias, use its target; otherwise use old_name
    target = s || old_name.to_s[1..-1]  # Strip $ prefix
    @aliases[new_name] = target
  end

  def add_constant(c,v = true)
    @globals[c] = v
  end

  def find_constant(c)
    @globals[c]
  end

  def rest?
    false
  end

  # Returns an argument within the global scope, if defined here.
  # Otherwise returns it as an address (<tt>:addr</tt>)
  def get_arg(a)
    # Handle $:, $0, $!, $@ etc. - map to assembly-safe aliases
    s = @aliases[a]
    if s
      @globals[s.to_sym] = true  # Register the ALIAS in globals, not the original
      return [:global, s]
    end

    return [:arg, 1] if a == :__argv
    return [:arg, 0] if a == :__argc

    # Auto-register global variables (starting with $)
    # Strip $ prefix to make assembly-safe
    if a && a.to_s[0] == ?$
      clean_name = a.to_s[1..-1]
      @globals[clean_name.to_sym] = true
      return [:global, clean_name]
    end

    return [:global, a] if @globals.member?(a)
    return [:possible_callm, a] if a && !(?A..?Z).member?(a.to_s[0]) # Hacky way of excluding constants
    return [:addr, a]
  end

  def name
    ""
  end

  def instance_size
    0
  end

  def lvaroffset
    0
  end

  def include_module m
  end
end
