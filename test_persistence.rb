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

class ClockedAddingSystem < AddingSystem
  include Madeleine::Clock::ClockedSystem
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
      File.delete(directory_name + File::SEPARATOR + file)
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


class ClockedPersistenceTest < PersistenceTest

  def create_madeleine
    Madeleine::Clock::ClockedSnapshotMadeleine.new(prevalence_base()) {
      ClockedAddingSystem.new
    }
  end

  def prevalence_base
    "ClockedPrevalenceBase"
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

class TimeTest < Test::Unit::TestCase

  def test_clock
    target = Madeleine::Clock::Clock.new
    assert_equal(0, target.time.to_i)
    assert_equal(0, target.time.usec)

    t1 = Time.at(10000)
    target.forward_to(t1)
    assert_equal(t1, target.time)
    t2 = Time.at(20000)
    target.forward_to(t2)
    assert_equal(t2, target.time)

    assert_nothing_raised() {
      target.forward_to(t2)
    }
    assert_raises(RuntimeError) {
      target.forward_to(t1)
    }
  end

  def test_time_actor
    @forward_calls = 0
    @last_time = Time.at(0)

    target = Madeleine::Clock::TimeActor.launch(self, 0.01)

    # When launch() has returned it should have sent
    # one synchronous clock-tick before it went to sleep
    assert_equal(1, @forward_calls)

    sleep(0.1)
    assert(@forward_calls > 1)
    target.destroy

    @forward_calls = 0
    sleep(0.1)
    assert_equal(0, @forward_calls)
  end

  # Self-shunt
  def execute_command(command)
    mock_system = self
    command.execute(mock_system)
  end

  # Self-shunt (system)
  def clock
    self
  end

  # Self-shunt (clock)
  def forward_to(time)
    if time <= @last_time
      raise "non-monotonous time"
    end
    @last_time = time
    @forward_calls += 1
  end

  def test_clocked_system
    target = Object.new
    target.extend(Madeleine::Clock::ClockedSystem)
    t1 = Time.at(10000)
    target.clock.forward_to(t1)
    assert_equal(t1, target.clock.time)
    t2 = Time.at(20000)
    target.clock.forward_to(t2)
    assert_equal(t2, target.clock.time)
    reloaded_target = Marshal.load(Marshal.dump(target))
    assert_equal(t2, reloaded_target.clock.time)
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

class TimeOptimizingCommandLogTest < CommandLogTest

  def setup
    @target = Madeleine::Clock::TimeOptimizingCommandLog.new(".")
  end

  def test_optimizing_ticks
    f = open(expected_file_name, 'r')
    assert(f.stat.file?)
    assert_equal(0, f.stat.size)
    @target.store(Madeleine::Clock::Tick.new(Time.at(3)))
    assert_equal(0, f.stat.size)
    @target.store(Madeleine::Clock::Tick.new(Time.at(22)))
    assert_equal(0, f.stat.size)
    @target.store(Addition.new(100))
    tick = Marshal.load(f)
    assert(tick.kind_of?(Madeleine::Clock::Tick))
    assert_equal(22, value_of_tick(tick))
    assert_equal(100, Marshal.load(f).value)
    assert_equal(f.stat.size, f.tell)
  end

  def value_of_tick(tick)
    @clock = Object.new
    def @clock.forward_to(time)
      @value = time.to_i
    end
    def @clock.value
      @value
    end
    tick.execute(self)
    @clock.value
  end

  # Self-shunt
  def clock
    @clock
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

  def test_changing_marshaller
    @log = ""
    marshaller = self
    target = Madeleine::SnapshotMadeleine.new(prevalence_base, marshaller) { "hello world" }
    target.take_snapshot
    assert_equal("dump ", @log)
    target = nil

    Madeleine::SnapshotMadeleine.new(prevalence_base, marshaller) { flunk() }
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
suite << ClockedPersistenceTest.suite
suite << TimeTest.suite
suite << TimeOptimizingCommandLogTest.suite
suite << CommandVerificationTest.suite
suite << CustomMarshallerTest.suite
suite << ErrorHandlingTest.suite

require 'test/unit/ui/console/testrunner'
Test::Unit::UI::Console::TestRunner.run(suite)
