$: << File.expand_path(File.dirname(__FILE__)+"/../..")
require 'operators'
require 'tokens'
require 'shunting'
require 'parser'
require 'spec/expectations'

class DummyParser
  def initialize s
    @s = s
  end

  def parse_block start
    close = (start.to_s) == "{" ? "}" : "end"
    @s.ws
    @s.expect(close) or raise "Expected #{start}"
    [:do]
  end
end

Given /^the expression (.*)$/ do |expr|
  @scanner = Scanner.new(StringIO.new(eval(expr)))
  @parser =  OpPrec::parser(@scanner,DummyParser.new(@scanner))
  @expr = expr
end

When /^I parse it with the shunting yard parser$/ do
  @tree = @parser.parse
end

Then /^the parse tree should become (.*)$/ do |tree|
  @tree.should == eval(tree)
end

Then /^the remainder of the scanner stream should be (.*)$/ do |remainder|
  r = eval(remainder)
  buf = ""
  while @scanner.peek; buf += @scanner.get; end
  buf.should == r
  @scanner.get.should == nil
end
