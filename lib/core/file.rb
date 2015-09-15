
class File

  def self.file?(io)
    false
  end

  def self.dirname(dname)
    STDERR.puts "dirname: #{dname}"
    "XXX"
  end

  def self.expand_path(path)
    STDERR.puts "expand_path: #{path}"
    "YYY"
  end
end
