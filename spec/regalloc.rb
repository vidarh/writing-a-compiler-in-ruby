
require_relative '../regalloc'
require 'set'

describe RegisterAllocator do

  let(:r) do
    r = RegisterAllocator.new
    r.order([:foo])
    r.registers = [:edx]
    r.caller_saved = []
    r
  end

  describe "#cache_reg!" do

    it "should return a register if one is available, and the variable is in the order set" do 
      expect(r.cache_reg!(:foo)).to eq(:edx)
    end

    it "should *not* return a register if one is available, but the variable is not in the order set" do 
      r.order([])
      expect(r.free_registers).to eq([:edx]), "There should be a free register"
      expect(r.cache_reg!(:foo)).to eq(nil)
    end

    it "should return nil when it runs out of registers" do
      expect(r.cache_reg!(:foo)).to eq(:edx)
      expect(r.free_registers).to eq([]), "There should be no free registers"
      expect(r.cache_reg!(:bar)).to eq(nil)
    end

    it "should return the same register again when requesting to cache the same variable twice" do
      expect(r.cache_reg!(:foo)).to eq(:edx)
      expect(r.cache_reg!(:foo)).to eq(:edx)
      expect(r.free_registers).to eq([]), "There should be no free registers"
    end
  end

  describe "with_register" do

    it "if a register has been previously cached, it should be evicted and reused" do
      r.order([:foo,:bar])
      expect(r.free_registers).to eq([:edx])
      expect(r.cache_reg!(:foo)).to eq(:edx)
      expect(r.free_registers).to eq([]), "There should be no free registers"
      r.with_register do |reg|
        expect(reg).to eq(:edx)
      end
      expect(r.cached_reg(:foo)).to eq(nil), "'foo' should have been evicted"
      expect(r.free_registers).to eq([:edx]), "The free_registers set should be back to what it was before #with_register"
    end

  end

end
