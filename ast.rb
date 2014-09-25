
module AST

  # Adds properties to AST nodes that simplify error
  # reporting, debugging etc.
  #
  # This will later also provide a location for
  # plugins to attach additional notation to the
  # nodes, such as inferred type information etc.
  module Node
    attr_accessor :position
  end

  # Inheriting from Array lets most code just work on the
  # expression as a raw set of data. And it avoids the hassle
  # of changing lots of code. At the same time, we can attach
  # extra data - we're sneaky like that.
  #
  # call-seq:
  #   Expr[1,2,3]
  #
  # When called with tokens from the scanner, it is the
  # intention that these tokens will *also* have a position
  # and carry position information, and that Expr's constructor
  # will default to take the position information of the first
  # node it is passed that respond_to?(:position).
  #
  # Alternatively, if the first argument is_a?(Scanner::Position)
  # it will be stripped and used as the position.
  class Expr < Array
    include Node

    def update_position
      sub = find{ |n| n.respond_to?(:position) }
      position = sub.position if sub
    end

    def self.[](*args)
      if args.size > 0 and args.first.is_a?(Scanner::Position) || args.first.nil?
        pos = args.shift
      end
      e = super(*args)
      if pos
        e.position = pos
      else
        e.update_position
      end
      e
    end

    def concat(other)
      super(other)
      update_position
      return self
    end

    def extra
      @extra ||= {}
    end
  end

  # For convenience
  E = Expr
end
