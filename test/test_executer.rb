
unless $LOAD_PATH.include?("lib")
  $LOAD_PATH.unshift("lib")
end
unless $LOAD_PATH.include?("test")
  $LOAD_PATH.unshift("test")
end

require 'madeleine'

class ExecuterTest < Minitest::Test

  def test_executer
    system = Object.new
    command = self
    executer = Madeleine::Executer.new(system)
    @executed_with_system = nil
    @executed_with_context = nil
    executer.execute(command)
    assert_same(system, @executed_with_system)
  end

  # Self-shunt
  def execute(system, context = :no_context)
    @executed_with_system = system
    @executed_with_context = context
  end

  def test_executer_with_context
    system = Object.new
    context = :custom_context
    command = self
    executer = Madeleine::Executer.new(system, context)
    @executed_with_system = nil
    @executed_with_context = nil
    executer.execute(command)
    assert_same(system, @executed_with_system)
    assert_same(context, @executed_with_context)
  end

  def test_execute_with_exception
    system = Object.new
    command = Object.new
    def command.execute(system)
      raise "this is an exception from a command"
    end
    executer = Madeleine::Executer.new(system)
    assert_raises(RuntimeError) {
      executer.execute(command)
    }
  end

  def test_exception_in_recovery
    system = Object.new
    command = Object.new
    def command.execute(system)
      raise "this is an exception from a command"
    end
    executer = Madeleine::Executer.new(system)
    executer.recovery {
      executer.execute(command)
    }
    assert_raises(RuntimeError) {
      executer.execute(command)
    }
  end
end
