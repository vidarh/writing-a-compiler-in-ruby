$: << File.expand_path(File.dirname(__FILE__)+"/../..")

require 'transform'

# The rest is shared with the parser steps

When(/^I preprocess it with the compiler transformations$/) do
  Compiler.new.preprocess(@tree)
end

