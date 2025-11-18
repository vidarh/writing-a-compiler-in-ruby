require_relative '../rubyspec/spec_helper'

describe "$LOAD_PATH.resolve_feature_path" do
  it "returns what will be loaded without actual loading, .so file" do
    require 'rbconfig'
    skip "no dynamically loadable standard extension" if RbConfig::CONFIG["EXTSTATIC"] == "static"

    extension, path = $LOAD_PATH.resolve_feature_path('etc')
    extension.should == :so
    path.should.end_with?("/etc.#{RbConfig::CONFIG['DLEXT']}")
  end
end
