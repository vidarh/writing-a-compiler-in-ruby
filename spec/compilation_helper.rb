# Helper module for compiling and running Ruby code in RSpec tests
module CompilationHelper
  # Compiles Ruby code, assembles it, and runs it in Docker
  # Returns the stdout output from the compiled binary
  def compile_and_run(code)
    require 'fileutils'

    src_file = "out/test_#{Process.pid}_#{rand(10000)}.rb"
    asm_file = "out/test_#{Process.pid}_#{rand(10000)}.s"
    exe_file = "out/test_#{Process.pid}_#{rand(10000)}"

    begin
      File.write(src_file, code)

      # Compile Ruby to assembly
      compile_result = system("ruby -I. driver.rb #{src_file} >#{asm_file} 2>#{asm_file}.err")
      unless compile_result
        err = File.read("#{asm_file}.err") if File.exist?("#{asm_file}.err")
        raise "Compilation failed: #{err}"
      end

      # Assemble to binary using Docker (for 32-bit support)
      asm_result = system("docker run --rm -v #{Dir.pwd}:/app ruby-compiler-buildenv gcc -m32 -gstabs -o /app/#{exe_file} /app/#{asm_file} /app/out/tgc.o 2>&1")
      unless asm_result
        raise "Assembly failed"
      end

      # Run the binary
      output = `docker run --rm -v #{Dir.pwd}:/app ruby-compiler-buildenv /app/#{exe_file}`.strip

      return output
    ensure
      FileUtils.rm_f([src_file, asm_file, exe_file, "#{asm_file}.err", "#{exe_file}.err"])
    end
  end
end