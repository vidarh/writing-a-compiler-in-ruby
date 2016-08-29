
require 'atom'
require 'quoted'

module Tokens

  class Sym
    def self.expect(s)
      return nil if s.peek != ?:
      s.get
      buf = Atom.expect(s)
      bs = ":#{buf.to_s}"
      return bs.to_sym if buf
      c = s.peek
      buf = Quoted.expect(s)
      bs = ":#{buf.to_s}"
      return bs.to_sym if buf

      # Lots more operators are legal.
      # FIXME: Need to check which set is legal - it's annoying inconsistent it appears
      if s.peek == ?[
        s.get
        if s.peek == ?]
          s.get
          return :":[]=" if s.peek == ?=
          return :":[]"
        end
        s.unget("[")
      elsif s.peek == ?/
        s.get
        return :":/"
      elsif s.peek == ?-
        s.get
        return :":-"
      elsif s.peek == ?+
        s.get
        return :":+"
      elsif s.peek == ?=
        s.get
        if s.peek == ?=
          s.get
          if s.peek == ?=
            s.get
            return :":==="
          end
          return :":=="
        end
        return :":="
      elsif s.peek == ?<
        s.get
        if s.peek == ?<
          s.get
          return :":<<"
        elsif s.peek == ?=
          s.get
          return :":<="
        end
        return :":<"
      elsif s.peek == ?>
        s.get
        if s.peek == ?>
          s.get
          return :":>>"
        elsif s.peek == ?=
          s.get
          return :":>="
        end
        return :":>"
      end
      s.unget(":")
      return nil
   end
  end
end
