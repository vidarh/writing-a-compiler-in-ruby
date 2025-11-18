# encoding: binary
require_relative '../../spec_helper'
require_relative '../fixtures/classes'

# TODO: synchronize with spec/core/regexp/new_spec.rb -
#       escaping is also tested there
describe "Regexps with escape characters" do
  it "does not change semantics of escaped non-meta-character when used as a terminator" do
    all_terminators = [*("!".."/"), *(":".."@"), *("[".."`"), *("{".."~")]
  end
end
