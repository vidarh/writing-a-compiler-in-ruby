require_relative '../rubyspec/spec_helper'

# KNOWN ISSUE: These specs compile successfully but segfault at runtime
# Root cause appears to be related to class naming/scoping - classes defined
# in lambdas get Object__ prefix when they shouldn't, leading to runtime errors
# See docs/nil_classscope_investigation.md and docs/KNOWN_ISSUES.md

describe "Class definition inside lambda" do
  it "allows defining classes inside lambdas" do
    l = lambda do
      class LambdaScopedClass
        def value
          42
        end
      end

      LambdaScopedClass.new.value
    end

    l.call.should == 42
  end

  it "does NOT re-execute class body when lambda is called multiple times" do
    # Class body should only execute once, on first definition
    # Use a class variable to track executions since we don't have closures working yet

    l = lambda do
      class MultiCallClass
        @@counter = 0 if !defined?(@@counter)
        @@counter = @@counter + 1

        def self.get_counter
          @@counter
        end
      end

      MultiCallClass.get_counter
    end

    first = l.call
    second = l.call
    third = l.call

    # Class body executed only once, so @@counter should be 1
    first.should == 1
    second.should == 1
    third.should == 1
  end

  it "does not recreate the class object when lambda is called multiple times" do
    l = lambda do
      class SameClassObject
        def test
          "works"
        end
      end

      SameClassObject.object_id
    end

    first_id = l.call
    second_id = l.call
    third_id = l.call

    first_id.should == second_id
    second_id.should == third_id
  end

  it "returns the value of the last expression in the class body" do
    l = lambda do
      class ClassWithReturn
        def foo
          1
        end

        def bar
          2
        end

        42  # Last expression
      end
    end

    l.call.should == 42
  end

  it "returns method name symbol when last expression is a method definition" do
    l = lambda do
      class ClassReturningMethodName
        def foo
          1
        end

        def last_method
          2
        end
      end
    end

    l.call.should == :last_method
  end

  it "allows classes defined between lambda calls to be accessible" do
    define_class = lambda do
      class BetweenLambdas
        def test
          "works"
        end
      end

      :defined
    end

    use_class = lambda do
      BetweenLambdas.new.test
    end

    define_class.call.should == :defined
    use_class.call.should == "works"
  end
end
