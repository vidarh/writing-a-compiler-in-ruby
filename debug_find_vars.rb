$: << "."
require 'driver'

class Compiler
  alias_method :orig_find_vars, :find_vars
  
  def find_vars(e, scopes, env, freq, in_lambda = false, in_assign = false, lambda_params = [])
    if e.is_a?(Array) && (e[0] == :lambda || e[0] == :proc)
      puts "=== Processing #{e[0]} node ==="
      puts "  Parameters: #{e[1].inspect}"
      puts "  lambda_params passed: #{lambda_params.inspect}"
      puts "  Current scopes: #{scopes.map(&:to_a).inspect}"
    end
    
    result = orig_find_vars(e, scopes, env, freq, in_lambda, in_assign, lambda_params)
    
    if e.is_a?(Array) && (e[0] == :lambda || e[0] == :proc)
      puts "  Returned env: #{result[1].inspect}"
    end
    
    result
  end
end

code = File.read('test_nested_simple.rb')
compiler = Compiler.new(['--norequire', '-I.'])
require 'stringio'
exp = compiler.parse(StringIO.new(code), '<test>')
compiler.preprocess(exp)
