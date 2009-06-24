$: << File.expand_path(File.dirname(__FILE__)+"/../..")
require 'compiler'
require 'spec/expectations'

# The rest is shared with the shunting yard steps

When /^I compile it$/ do
  @parser = Parser.new(@scanner,{:norequire => true})
  @ptree = @parser.parse
  @aout = ArrayOutput.new
  @emitter = Emitter.new(@aout)
  @emitter.basic_main = true
  @compiler = Compiler.new(@emitter)
  @compiler.compile(@ptree)
  @tree = @aout.output
end

Then /^the output should be (.*)$/ do |tree|
  @tree.should == eval(tree)
end
