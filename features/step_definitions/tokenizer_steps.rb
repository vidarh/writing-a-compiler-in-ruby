$: << File.expand_path(File.dirname(__FILE__)+"/../..")
require 'operators'
require 'tokens'

When(/^I tokenize it with the (\w+) tokenizer$/) do |tokenizer|
  @result = eval(tokenizer).expect(@scanner)
end

Then(/^the result should be (.*)$/) do |res|
  @result.should be eval(res)
end

