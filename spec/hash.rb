
module Test
  eval(File.read(File.expand_path(File.dirname(__FILE__)+'/../lib/core/hash.rb')))
  eval(File.read(File.expand_path(File.dirname(__FILE__)+'/../lib/core/hash_ext.rb')))
end

describe Hash do
  it "should return inserted items in insertion order" do
    h = Test::Hash.new
    h["xyz"] = 1
    h["abc"] = 2
    h["ghi"] = 3
    h["def"] = 4
    h.to_a.should eq [["xyz",1],["abc",2],["ghi",3],["def",4]]
  end

  it "should return inserted items in insertion order after a #delete" do
    h = Test::Hash.new
    h["xyz"] = 1
    h["abc"] = 2
    h["ghi"] = 3
    h["def"] = 4
    h.delete("abc")
    h.to_a.should eq [["xyz",1],["ghi",3],["def",4]]
  end

  it "should return inserted items in insertion order after a #delete and re-insert" do
    h = Test::Hash.new
    h["xyz"] = 1
    h["abc"] = 2
    h["ghi"] = 3
    h["def"] = 4
    h.delete("abc")
    h["abc"] = 5
    h.to_a.should eq [["xyz",1],["ghi",3],["def",4],["abc", 5]]
  end

  it "after a reinsert with the same key, there should be no Deleted entries" do
    h = Test::Hash.new
    h["xyz"] = 1
    p h._data
    h.delete("xyz").should eq 1
    p h._state
    p h._data
    h["xyz"] = 1
    p h._state
    p h._data
    h._data.compact.should eq ["xyz", 1]
    h.to_a.should eq [["xyz", 1]]

    h["abc"] = 2
    # FIXME: The result of this is unstable because
    # `#hash` changes from run to run under MRI
    #h._data.compact.should eq ["xyz", 1,24, "abc", 2, 0]
    h.to_a.should eq [["xyz", 1], ["abc", 2]]
    p :xyz_abc
    p h._state
    p h._data
    h.delete("xyz").should eq 1
    p :abc
    p h._state
    p h._data
    h.to_a.should eq [["abc", 2]]
    h["xyz"] = 3
    p :abc_xyz
    p h._state
    p h._data
    h.to_a.should eq [["abc", 2], ["xyz", 3]]
  end
end
