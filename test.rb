#!/usr/local/bin/ruby -w
#

$LOAD_PATH.unshift("lib")

require 'madeleine'
require 'test/unit'


class Append
  def initialize(value)
    @value = value
  end

  def execute(system)
    system << @value
  end
end


module TestUtils
  def delete_directory(directory_name)
    Dir.foreach(directory_name) do |file|
      next if file == "."
      next if file == ".."
      assert(File.delete(directory_name + File::SEPARATOR + file) == 1,
             "Unable to delete #{file}")
    end
    Dir.delete(directory_name)
  end
end


class SnapshotMadeleineTest < Test::Unit::TestCase
  include TestUtils

  def teardown
    delete_directory(persistence_base)
  end

  def persistence_base
    "closing-test"
  end

  def test_closing
    madeleine = SnapshotMadeleine.new(persistence_base) { "hello" }
    madeleine.close
    assert_raises(RuntimeError) do
      madeleine.execute_command(Append.new("world"))
    end
  end
end

class NumberedFileTest < Test::Unit::TestCase

  def test_main
    target = Madeleine::NumberedFile.new(File::SEPARATOR + "foo", "bar", 321)
    assert_equal(File::SEPARATOR + "foo" + File::SEPARATOR +
                 "000000000000000000321.bar",
                 target.name)
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
    @target.store(Addition.new(7))
    read_command = Marshal.load(f)
    assert_equal(Addition, read_command.class)
    assert_equal(7, read_command.value)
    assert_equal(f.stat.size, f.tell)
    @target.store(Addition.new(3))
    read_command = Marshal.load(f)
    assert_equal(3, read_command.value)
    assert_equal(f.stat.size, f.tell)
    f.close
  end

  def expected_file_name
    "000000000000000000001.command_log"
  end
end


class LoggerTest < Test::Unit::TestCase

  def test_creation
    @log = Object.new
    def @log.store(command)
      unless defined? @commands
        @commands = []
      end
      @commands << command
    end
    def @log.commands
      @commands
    end

    log_factory = self
    target = Madeleine::Logger.new("whoah", log_factory)
    target.store(:foo)
    assert(@log.commands.include?(:foo))
  end

  # Self-shunt
  def create_log(directory_name)
    @log
  end
end

class CommandVerificationTest < Test::Unit::TestCase

  def teardown
    Dir.delete("foo")
  end

  def test_broken_command
    target = SnapshotMadeleine.new("foo") { :a_system }
    assert_raises(Madeleine::InvalidCommandException) do
      target.execute_command(:not_a_command)
    end
  end
end


class CustomMarshallerTest < Test::Unit::TestCase
  include TestUtils

  def teardown
    delete_directory(prevalence_base)
  end

  def prevalence_base
    "custom-marshaller-test"
  end

  def madeleine_class
    SnapshotMadeleine
  end

  def test_changing_marshaller
    @log = ""
    marshaller = self
    target = madeleine_class.new(prevalence_base, marshaller) { "hello world" }
    target.take_snapshot
    assert_equal("dump ", @log)
    target = nil

    madeleine_class.new(prevalence_base, marshaller) { flunk() }
    assert_equal("dump load ", @log)
  end

  def load(io)
    @log << "load "
    assert_equal("dump data", io.read())
  end

  def dump(system, io)
    @log << "dump "
    assert_equal("hello world", system)
    io.write("dump data")
  end
end


class ErrorRaisingCommand
  def execute(system)
    raise "woo-hoo"
  end
end

class ErrorHandlingTest < Test::Unit::TestCase
  include TestUtils

  def teardown
    delete_directory(prevalence_base)
  end

  def prevalence_base
    "error-handling-base"
  end

  def test_exception_in_command
    madeleine = SnapshotMadeleine.new(prevalence_base) { "hello" }
    assert_raises(RuntimeError) do
      madeleine.execute_command(ErrorRaisingCommand.new)
    end
    madeleine.close
    madeleine = SnapshotMadeleine.new(prevalence_base) { "hello" }
    madeleine.close
  end
end


suite = Test::Unit::TestSuite.new("Madeleine")

suite << SnapshotMadeleineTest.suite
suite << NumberedFileTest.suite
suite << CommandLogTest.suite
suite << LoggerTest.suite
suite << CommandVerificationTest.suite
suite << CustomMarshallerTest.suite
suite << ErrorHandlingTest.suite

require 'test_clocked'
add_clocked_tests(suite)
require 'test_automatic'
add_automatic_tests(suite)
require 'test_persistence'
add_persistence_tests(suite)

require 'test/unit/ui/console/testrunner'
Test::Unit::UI::Console::TestRunner.run(suite)
