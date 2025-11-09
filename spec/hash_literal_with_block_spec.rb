require_relative '../rubyspec/spec_helper'

# This spec documents a compiler bug where passing a hash literal
# as an argument to a method that also takes a block causes a runtime error:
# "undefined method 'pair' for Object"
#
# The code compiles successfully but fails at runtime when the hash is accessed.
#
# Related to KNOWN_ISSUES.md - this is why platform_is guards don't work
# properly and must be preprocessed to skip 64-bit tests. The preprocessor
# converts `platform_is c_long_size: 64` to `if false` to avoid this bug.

# Define test method at top level to avoid block-in-block issues
def hash_arg_block_test(*args)
  if block_given?
    result = args[0][:value]
    yield
    result
  end
end

describe "Hash literal as argument with block" do
  it "should work with hash rocket syntax" do
    # This test FAILS with runtime error - documenting the bug
    # The hash compiles fine, but accessing it causes:
    # "undefined method 'pair' for Object"

    # This should work but causes runtime error
    result = hash_arg_block_test({:value => 42}) do
      puts "Block executed"
    end

    result.should == 42
  end

  it "should work with simple hash access" do
    # For comparison - this works fine (no block involved)
    hash = {:value => 42}
    hash[:value].should == 42
  end
end
