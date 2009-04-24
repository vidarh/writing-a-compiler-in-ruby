
module AST

  # Adds properties to AST nodes that simplify error
  # reporting, debugging etc.
  module Node
    class <<
        attr_accessor :lineno,:col,:filename
    end

    Position = Struct.new(:filename,:lineno,:col)

    def position= pos
      @lineno = pos.lineno
      @col = pos.col
      @filename = pos.filename
    end

    def position
      Position.new(@filename,@lineno,@col)
    end
  end

  # Inheriting from Array lets most code just work on the
  # expression as a raw set of data. And it avoids the hassle
  # of changing lots of code. At the same time, we can attach
  # extra data - we're sneaky like that.
  #
  # call-seq:
  #   Expr[1,2,3]
  #
  # FIXME: When called with tokens from the scanner, it is the
  # intention that these tokens will *also* include Node
  # and carry position information, and that Expr's constructor
  # will default to take the position information of the first
  # node it is passed that is_a?(AST::Node)
  class Expr < Array
    include Node

    def self.[] *args
      e = super *args
      sub = e.find {|n| n.is_a?(Node) }
      e.position = sub.position if sub
      e
    end
  end

  # For convience
  E = Expr
end
