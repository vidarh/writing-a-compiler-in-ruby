require '../scanner'
require 'spec/expectations'

Given /^there are two different characters in the stream$/ do
  @stream = StringIO.new("ab")
  @scanner = Scanner.new(@stream)
end

# ----------- When

When /^calling get (\d+) times?$/ do |n|
  @prev_results = @results
  @results ||= []
  n.to_i.times { @results << @scanner.get }
end

When /^calling peek twice$/ do
  @peeks = []
  2.times { @peeks << @scanner.peek }
end

When /^calling unget with the returned characters?$/ do
  @results and @results[0] and @scanner.unget(@results[0])
end

When /^calling unget once with a string consisting of both characters$/ do
  @results and @results.size == 2 and @scanner.unget(@results.join)
end

# ----------- Then

Then /^the first character in the stream should be returned both times$/ do
  @prev_results[0].should == "a"
  @results[0].should == "a"
end

Then /^both characters should be returned( followed by nil)?$/ do |followed|
  @results[0].should == "a"
  @results[1].should == "b"
  if followed
    @results.size.should == 3
    @results[2].should == nil
  end
end

Then /^the same character should be returned both times$/ do
  @peeks[0].should == ?a
  @peeks[1].should == ?a
end
