# Compare two assembler outputs line by line and report the first diff.
# Usage: ruby tools/compare_asm.rb old.s new.s

require 'digest'

old, newf = ARGV
abort "Usage: ruby tools/compare_asm.rb old.s new.s" unless old && newf

def digest(path)
  Digest::SHA256.file(path).hexdigest
end

def first_diff(a, b)
  File.open(a) do |fa|
    File.open(b) do |fb|
      lineno = 0
      loop do
        la = fa.gets
        lb = fb.gets
        lineno += 1
        return [lineno, la, lb] if la != lb
        break if la.nil? && lb.nil?
      end
    end
  end
  nil
end

old_hash = digest(old)
new_hash = digest(newf)

if old_hash == new_hash
  puts "Files are identical (sha256=#{old_hash})"
  exit 0
end

if (diff = first_diff(old, newf))
  lineno, la, lb = diff
  puts "Files differ at line #{lineno}:"
  puts "- #{la.inspect}"
  puts "+ #{lb.inspect}"
else
  puts "Files differ but no differing line found (length mismatch?)"
end

puts "Old sha256: #{old_hash}"
puts "New sha256: #{new_hash}"
