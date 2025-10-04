$: << File.dirname(__FILE__) + "/.."
require 'parser'
require 'tokens'

class MockIO
  def initialize(str)
    @str = str
    @pos = 0
  end

  def getc
    return nil if @pos >= @str.length
    c = @str[@pos]
    @pos += 1
    c
  end

  def ungetc(c)
    @pos -= 1 if @pos > 0
  end
end

RSpec.describe "Lambda chained method calls" do
  it "parses lambda { }.call without error" do
    p = Parser.new(Scanner.new(MockIO.new('lambda { 42 }.call')))
    result = p.parse_exp
    expect(result).to be_a(Array)
    expect(result[0]).to eq(:callm)
    expect(result[1][0]).to eq(:lambda)
  end

  it "parses lambda { x; y }.call correctly" do
    p = Parser.new(Scanner.new(MockIO.new('lambda { 42; 99 }.call')))
    result = p.parse_exp
    expect(result).to be_a(Array)
    expect(result[0]).to eq(:callm)
    expect(result[1][0]).to eq(:lambda)
    expect(result[1][2]).to eq([42, 99])
  end

  it "converts lambda { } to lambda node (not call node)" do
    p = Parser.new(Scanner.new(MockIO.new('lambda { 42 }')))
    result = p.parse_exp
    expect(result[0]).to eq(:lambda)
    expect(result[1]).to eq([])  # args
    expect(result[2]).to eq([42]) # body
  end
end
