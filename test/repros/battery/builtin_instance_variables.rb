# instance_variables on a built-in (or its subclass) must not hand back the raw internal storage
# ivars (@ptr/@len/@buffer...) -- calling .nil? on a raw pointer segfaulted. They're excluded from
# the reflection table (Compiler#IVAR_TABLE_EXCLUDE), so these read back empty like MRI.
raise "arr" unless [1,2].instance_variables == []
raise "str" unless "x".instance_variables == []
raise "hash" unless({a: 1}.instance_variables == [])
puts "ok"
