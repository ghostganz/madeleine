
unless $LOAD_PATH.include?("lib")
  $LOAD_PATH.unshift("lib")
end
unless $LOAD_PATH.include?("test")
  $LOAD_PATH.unshift("test")
end

require 'madeleine'
require 'test/unit'

class ExampleCommand
  attr :value

  def initialize(value)
    @value = value
  end

  def execute(system)
    system.add(@value)
  end
end

class CommandLogTest < Test::Unit::TestCase

  def setup
    @target = Madeleine::CommandLog.new(".")
  end

  def teardown
    @target.close
    File.delete(expected_file_name)
  end

  def test_logging
    f = open(expected_file_name, 'r')
    assert(f.stat.file?)
    @target.store(ExampleCommand.new(7))
    read_command = Marshal.load(f)
    assert_equal(ExampleCommand, read_command.class)
    assert_equal(7, read_command.value)
    assert_equal(f.stat.size, f.tell)
    @target.store(ExampleCommand.new(3))
    read_command = Marshal.load(f)
    assert_equal(3, read_command.value)
    assert_equal(f.stat.size, f.tell)
    f.close
  end

  def expected_file_name
    "000000000000000000001.command_log"
  end
end
