require "minitest/autorun"
require_relative "../peephole"

class StringOut
  attr_reader :lines
  def initialize
    @lines = []
  end
  def emit(*args)
    @lines << args
  end
  def export(*); end
  def label(*); end
end

class PeepholeFixtureTest < Minitest::Test
  def setup
    @out = StringOut.new
    @peephole = Peephole.new(@out)
  end

  def render(lines)
    lines.each { |l| @peephole.emit(*l) }
    @peephole.flush
    @out.lines
  end

  def test_no_change_on_unrelated_sequence
    input = [[:movl, :ebx, :eax], [:movl, :eax, :ecx]]
    assert_equal input, render(input)
  end
end
