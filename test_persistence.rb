#!/usr/local/bin/ruby -w
#
# Copyright(c) 2003 Anders Bengtsson
#
# PersistenceTest is based on the unit tests from Prevayler,
# Copyright(c) 2001-2003 Klaus Wuestefeld.
#

$LOAD_PATH.unshift("lib")

require 'madeleine'
require 'test/unit'

class AddingSystem
  attr_reader :total

  def initialize
    @total = 0
  end

  def add(value)
    @total += value
    @total
  end
end


class Addition

  attr_reader :value

  def initialize(value)
    @value = value
  end

  def execute(system)
    system.add(@value)
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

class PersistenceTest < Test::Unit::TestCase

  def setup
    @madeleines = []
    @madeleine = nil
  end

  def teardown
    delete_prevalence_files(prevalence_base)
    Dir.delete(prevalence_base)
  end

  def verify(expected_total)
    assert_equal(expected_total, prevalence_system().total(), "Total")
  end

  def prevalence_system
    @madeleine.system
  end

  def prevalence_base
    "PrevalenceBase"
  end

  def clear_prevalence_base
    @madeleines.each {|madeleine|
      madeleine.take_snapshot
    }
    @madeleines.clear
    delete_prevalence_files(prevalence_base())
  end

  def delete_prevalence_files(directory_name)
    return unless File.exist?(directory_name)
    Dir.foreach(directory_name) {|file_name|
      next if file_name == '.'
      next if file_name == '..'
      file_name.untaint
      assert(File.delete(directory_name + File::SEPARATOR + file_name) == 1,
                  "Unable to delete #{file_name}")
    }
  end

  def crash_recover
    @madeleine = create_madeleine()
    @madeleines << @madeleine
  end

  def create_madeleine
    Madeleine::SnapshotMadeleine.new(prevalence_base()) { AddingSystem.new }
  end

  def snapshot
    @madeleine.take_snapshot
  end

  def add(value, expected_total)
    total = @madeleine.execute_command(Addition.new(value))
    assert_equal(expected_total, total, "Total")
  end

  def verify_snapshots(expected_count)
    count = 0
    Dir.foreach(prevalence_base) {|name|
      if name =~ /\.snapshot$/
        count += 1
      end
    }
    assert_equal(expected_count, count, "snapshots")
  end

  def test_main
    clear_prevalence_base

    # There is nothing to recover at first.
    # A new system will be created.
    crash_recover

    crash_recover
    add(40,40)
    add(30,70)
    verify(70)

    crash_recover
    verify(70)

    add(20,90)
    add(15,105)
    verify_snapshots(0)
    snapshot
    verify_snapshots(1)
    snapshot
    verify_snapshots(2)
    verify(105)

    crash_recover
    snapshot
    add(10,115)
    snapshot
    add(5,120)
    add(4,124)
    verify(124)

    crash_recover
    add(3,127)
    verify(127)

    verify_snapshots(4)

    clear_prevalence_base
    snapshot

    crash_recover
    add(10,137)
    add(2,139)
    crash_recover
    verify(139)
  end

  def test_main_in_safe_level_one
    thread = Thread.new {
      $SAFE = 1
      test_main
    }
    thread.join
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
    target = Madeleine::SnapshotMadeleine.new("foo") { :a_system }
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
    Madeleine::SnapshotMadeleine
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
    madeleine = Madeleine::SnapshotMadeleine.new(prevalence_base) { "hello" }
    assert_raises(RuntimeError) do
      madeleine.execute_command(ErrorRaisingCommand.new)
    end
    Madeleine::SnapshotMadeleine.new(prevalence_base) { "hello" }
  end
end


suite = Test::Unit::TestSuite.new("Madeleine")
suite << NumberedFileTest.suite
suite << CommandLogTest.suite
suite << LoggerTest.suite
suite << PersistenceTest.suite
suite << CommandVerificationTest.suite
suite << CustomMarshallerTest.suite
suite << ErrorHandlingTest.suite

require 'test_clocked'
add_clocked_tests(suite)


require 'test/unit/ui/console/testrunner'
Test::Unit::UI::Console::TestRunner.run(suite)
