require "minitest/autorun"
require_relative "../peephole"

# Minimal output sink to capture emitted instructions
class CaptureOut
  attr_reader :emitted

  def initialize
    @emitted = []
  end

  def emit(*args)
    @emitted << args
  end

  def export(*); end
  def label(*); end
  def comment(*); end
end

class PeepholeTest < Minitest::Test
  def setup
    @out = CaptureOut.new
    @peephole = Peephole.new(@out)
  end

  def flush
    @peephole.flush
    @out.emitted
  end

  def test_subl_zero_is_removed
    @peephole.emit(:subl, 0, :eax)
    assert_empty flush
  end

  def test_movl_eax_to_eax_is_removed
    @peephole.emit(:movl, :eax, :eax)
    assert_empty flush
  end

  def test_push_pop_same_register_is_removed
    @peephole.emit(:pushl, :edi)
    @peephole.emit(:popl, :edi)
    assert_empty flush
  end

  def test_push_eax_pop_reg_becomes_mov
    @peephole.emit(:pushl, :eax)
    @peephole.emit(:popl, :esi)
    assert_equal [[:movl, :eax, :esi]], flush
  end

  def test_mov_imm_eax_then_cmpl_eax_becomes_cmpl_imm
    @peephole.emit(:movl, 5, :eax)
    @peephole.emit(:cmpl, :eax, :ecx)
    assert_equal [[:cmpl, 5, :ecx]], flush
  end

  def test_add_then_sub_same_dest_folds
    @peephole.emit(:addl, 7, :esp)
    @peephole.emit(:subl, 3, :esp)
    assert_equal [[:addl, 4, :esp]], flush
  end

  def test_two_sub_same_dest_fold
    @peephole.emit(:subl, 2, :esp)
    @peephole.emit(:subl, 5, :esp)
    assert_equal [[:subl, 7, :esp]], flush
  end

  def test_mov_chain_forwarding
    @peephole.emit(:movl, :esi, :eax)
    @peephole.emit(:movl, :eax, :edi)
    @peephole.emit(:movl, :ebx, :eax)
    assert_equal [[:movl, :esi, :edi], [:movl, :ebx, :eax]], flush
  end

  def test_mov_const_subl_fold
    @peephole.emit(:movl, 2, :eax)
    @peephole.emit(:subl, :eax, :edi)
    @peephole.emit(:movl, :ebx, :eax)
    assert_equal [[:subl, 2, :edi], [:movl, :ebx, :eax]], flush
  end
end
