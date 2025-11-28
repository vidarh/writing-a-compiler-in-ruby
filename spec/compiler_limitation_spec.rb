require_relative '../rubyspec/spec_helper'

# These specs test constructs that were initially claimed to cause selftest-c crashes
# Investigation showed: These constructs work fine in isolation!
# The actual issue is more subtle - modifying Symbol#inspect causes crashes
# when compiling large files, but works for small test cases.

describe "Compiler constructs" do
  describe "String#include? in conditionals" do
    it "works with simple include? check" do
      s = "hello world"
      result = s.include?(" ")
      result.should == true
    end

    it "works with include? in if statement" do
      s = "foo bar"
      if s.include?(" ")
        result = "has space"
      else
        result = "no space"
      end
      result.should == "has space"
    end

    it "works with multiple include? checks using ||" do
      s = "hello"
      result = s.include?(" ") || s.include?("\n")
      result.should == false
    end

    it "works with include? on instance variable in class" do
      class TestIncludeClass
        attr_reader :name
        def initialize(n)
          @name = n
        end
        def has_space?
          @name.include?(" ")
        end
      end
      obj = TestIncludeClass.new("foo bar")
      obj.has_space?.should == true
    end
  end

  describe "While loops with compound conditions" do
    it "works with simple while loop" do
      i = 0
      while i < 3
        i = i + 1
      end
      i.should == 3
    end

    it "works with while and compound &&" do
      i = 0
      flag = true
      while i < 5 && flag
        i = i + 1
        flag = false if i == 3
      end
      i.should == 3
    end

    it "works with while and !variable" do
      done = false
      count = 0
      while !done
        count = count + 1
        done = true if count >= 2
      end
      count.should == 2
    end
  end

  describe "Symbol#inspect" do
    # KNOWN BUG: Symbol#inspect doesn't quote symbols with spaces
    # Fixing this causes selftest-c crashes when compiling large files
    # (small test cases work fine)
    it "doesn't quote simple symbols" do
      s = :hello
      s.inspect.should == ":hello"
    end

    it "currently doesn't quote symbols with spaces (known bug)" do
      s = :"foo bar"
      # This documents current (incorrect) behavior
      # Should be: s.inspect.should == ":\"foo bar\""
      s.inspect.should == ":foo bar"
    end
  end
end
