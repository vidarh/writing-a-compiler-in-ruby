$: << File.expand_path(File.dirname(__FILE__)+"/../..")
require 'operators'
require 'tokens'
require 'shunting'
require 'parser'
require 'spec/expectations'

# The rest is shared with the shunting yard steps

When /^I parse it with the full parser$/ do
  @parser = Parser.new(@scanner)
  @tree = @parser.parse
end

