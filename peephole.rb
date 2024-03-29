
# # Very basic peephole optimizer
#
# This is *not* intended to be a general purpose peephole optimizer
# It's a quick and dirty hack to encapsulate optimizations that can
# be made quickly on the asm that is harder to fix in the higher level
# code generation. It is allowed to make assumptions about the generated
# code which may not hold for asm generated by anything else.
#
# This is i386 specific at the moment


class Peephole
  def initialize out
    @out = out
    @prev = []
  end

  def comment(str)
    #flush
    #@out.comment(str)
  end

  def export(label, type = nil)
    flush
    @out.export(label, type)
  end

  def label(l)
    flush
    @out.label(l)
  end

  def match(pat, test)
    return nil if pat.length != test.length
    res = []
    pat.each_with_index do |c,i|
      if c === test[i]
        res << test[i]
      else
        return nil
      end
    end
    return res
  end

  # Other patterns:
  # pushl %eax
  # movl ?, %eax
  # movl %eax, otherreg
  # popl %eax
  # ->
  # movl ?, reg

  # subl n, %esp
  # ... x ops not touching %esp
  # addl n, %esp
  # ->
  # ... x ops not touching %esp
  # *especially improving __int and __get_symbol init
  # Alt is handling the addl n, %esp/single instr not touching esp/subl n, %esp
  #
  # movl -n(%ebp), %eax
  # movl %eax, reg
  # popl %eax
  # movl %eax, (reg)
  # ->
  # movl -n(%ebp), reg
  # popl %eax
  # movl %eax, (reg)
  #
  #
  # subl x, %esp
  # op ?, reg
  # subl y, %esp
  # ->
  # subl x+y, %esp
  # op ?, reg
  #
  #
  # This *can't* be optimal:
  # movl n, %eax
  # cmpl %eax, %eax
  # setne %al
  # movzbl %al, %eax
  # testl %eax, %eax
  # je label
  #
  # Surely:
  # cmpl n, %eax
  # je label
  # must be enough?
  #
  #
  # movl n(%ebp), %esi
  # movl n(%ebp), %eax
  # must be a bug?
  #
  # movl -n(%ebp), %edx
  # pushl %edx
  # movl m(%ebp), %esi
  # popl %edi
  # movl %edi, o(%esi)
  # ->
  #movl m(%ebp), %esi
  #movl -n(%ebp), %edx
  #movl %edx, o(%esi)

  def peephole
    return if @prev.empty?

    args = @prev[-1]
    last = @prev[-2]

    # subl $0, reg
    if match([:subl, 0, Symbol], args)
      @prev.pop
      return
    end

    if args == [:movl, :eax, :eax]
      @prev.pop
      return
    end

    if last
      if last == [:pushl, :ebx] && args == [:movl, "-4(%ebp)", :eax]
        @prev.pop
        @prev << [:movl, :ebx, :eax]
        return
      end

      #if match([:movl, String, :eax], last) &&
      #  match([:movl, :eax, String], args)
      #  @prev.pop
      #  @prev.pop
      #  @prev << [:movl, last[1], args[2]]
      #  return
      #end

      if last == [:pushl, :eax] &&
        match([:popl, Symbol], args)
        # @unsafe Only ok because we know the compiler treats %eax as scratch
        @prev.pop
        @prev.pop
        @prev << [:movl, :eax, args[1]]
        return
      end

      if match([:movl, Integer, :eax], last) &&
         match([:cmpl, :eax, Symbol], args)
          # @unsafe this optimization is ok only because we know the compiler treats
          # %eax as a scratch register
        @prev.pop
        @prev.pop
        @prev << [:cmpl, last[1], args[2]]
        return
      end

      if last[0] == :pushl && args[0] == :popl && last[1] == args[1]
        @prev.pop
        @prev.pop
        return
      end

      if args[0] == :subl &&
        last[1].is_a?(Integer) &&
        args[1].is_a?(Integer) && last[2] == args[2]

        if last[0] == :addl &&
          # addl x, dest
          # subl y, dest
          @prev.pop
          @prev.pop
          if last[1] > args[1]
            @prev << [:addl, last[1] - args[1], args[2]]
            return
          elsif last[1] < args[1]
            @prev << [:subl, args[1] - last[1], args[2]]
          end
          return
        end

        if last[0] == :subl
          # subl x, dest
          # subl y, dest
          @prev.pop
          @prev.pop
          @prev << [:subl, args[1] + last[1], args[2]]
          return
        end
      end

      last2 = @prev[-3]
      if last2

        if last2[0] == :movl
          if last2[2] == :eax
            # movl ???, %eax

            if last2[1].class == Symbol
              src = last2[1]
              if last[0] == :movl && last[1] == :eax
                # movl reg, %eax
                # movl %eax, dest
                dest = last[2]

                if args[0] == :movl && args[2] == :eax
                  #movl reg, %eax
                  #movl %eax, dest
                  #movl ???, %eax
                  #->
                  #movl reg, dest
                  #movl ???, %eax
                  @prev.pop
                  @prev.pop
                  @prev.pop
                  @prev << [:movl, src, dest]
                  @prev << args
                  return
                end
              end
            end

            if last2[1].class == Symbol || last2[1].is_a?(Integer)
              val = last2[1]
              # movl Int|Reg, %eax

              if last[0] == :subl
                if last[1] == :eax
                  if last[2].class == Symbol
                    reg = last[2]
                    # movl $2, %eax
                    # subl %eax, reg

                    if args[0] == :movl
                      if args[1] != :eax
                        if args[2] == :eax
                          # movl $2, %eax
                          # subl %eax, reg
                          # movl ???, %eax
                          @prev.pop
                          @prev.pop
                          @prev.pop
                          @prev << [:subl, val, reg]
                          @prev << args
                          return
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def emit(*args)
    @prev << args
    l = @prev.length
    while l > 0
      peephole
      return if @prev.length >= l
      l = @prev.length
    end
  end

  def flush
    @prev.each do |row|
      @out.emit(*row)
    end
    @prev = []
  end
end
