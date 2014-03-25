
$: << File.dirname(__FILE__)+"/.."

require 'regalloc'
require 'set'

describe RegisterAllocator do

  describe "#cache_reg!" do

    it "should return a register if one is available, and the variable is in the order set" do 
      r = RegisterAllocator.new
      r.order(Set[:foo])
      r.registers = [:edx]
      expect(r.cache_reg!(:foo)).to eq(:edx)
    end

    it "should *not* return a register if one is available, but the variable is not in the order set" do 
      r = RegisterAllocator.new
      r.registers = [:edx]
      expect(r.cache_reg!(:foo)).to eq(nil)
    end

    it "should return nil when it runs out of registers" do
      r = RegisterAllocator.new
      r.order(Set[:foo])
      r.registers = [:edx]
      expect(r.cache_reg!(:foo)).to eq(:edx)
      expect(r.cache_reg!(:bar)).to eq(nil)
    end

    it "should return the same register again when requesting to cache the same variable twice" do
      r = RegisterAllocator.new
      r.order(Set[:foo])
      r.registers = [:edx]
      expect(r.cache_reg!(:foo)).to eq(:edx)
      expect(r.cache_reg!(:foo)).to eq(:edx)
    end

  end

end
