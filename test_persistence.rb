#!/usr/local/bin/ruby -w
#
# Copyright(c) 2003 Anders Bengtsson
#
# Based on the unit tests from Prevayler,
# Copyright(c) 2001-2003 Klaus Wuestefeld.
#

require 'madeleine'

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

  def initialize(value)
    @value = value
  end

  def execute(system)
    system.add(@value)
  end
end


class Test

  def verify_true(condition, message)
    unless condition
      raise message
    end
  end
end

class PersistenceTest < Test

  def initialize
    @prevaylers = []
    @prevayler = nil
  end

  def verify(expected_total)
    compare(prevalence_system().total(), expected_total, "Total");
  end

  def prevalence_system
    @prevayler.system
  end

  def prevalence_base
    "PrevalenceBase"
  end

  def clear_prevalence_base
    @prevaylers.each {|prevayler|
      prevayler.take_snapshot
    }
    @prevaylers.clear
    delete_prevalence_files(prevalence_base())
  end

  def delete_prevalence_files(directory_name)
    return unless File.exist?(directory_name)
    Dir.foreach(directory_name) {|file_name|
      next if file_name == '.'
      next if file_name == '..'
      verify_true(File.delete(directory_name + File::SEPARATOR + file_name) == 1,
                  "Unable to delete #{file_name}")
    }
  end

  def crash_recover
    @prevayler =
      Madeleine::SnapshotPrevayler.new(AddingSystem.new, prevalence_base())
    @prevaylers << @prevayler
  end

  def snapshot
    @prevayler.take_snapshot
  end

  def add(value, expected_total)
    total = @prevayler.execute_command(Addition.new(value))
    compare(total, expected_total, "Total");
  end

  def compare(observed, expected, message)
    verify_true(observed == expected,
                "#{message}: #{observed}   Expected: #{expected}")
  end

  def verify_snapshots(expected_count)
    count = 0
    Dir.foreach(prevalence_base) {|name|
      if name =~ /\.snapshot$/
        count += 1
      end
    }
    compare(count, expected_count, "snapshots")
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

    puts "OK"
  end
end


test = PersistenceTest.new
test.test_main

