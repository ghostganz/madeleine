#!/usr/local/bin/ruby -w
#
# Copyright(c) 2003 Håkan Råberg
#
# Some components taken from test_persistence.rb
# Copyright(c) 2003 Anders Bengtsson
#

$LOAD_PATH.unshift("../lib")

require 'batched'
require 'test/unit'
require 'sync'

class BatchedSnapshotMadeleineTest < Test::Unit::TestCase

  class PushTransaction
    def initialize(text)
      @text = text
    end

    def execute(system)
      system << @text
    end
  end  

  def test_live_snapshot
    system = []
    going = true

    madeleine = BatchedSnapshotMadeleine.new(prevalence_base) { system }

    5.times do 
      Thread.new {
        i = 1
        while going
          madeleine.execute_command(PushTransaction.new(i.to_s + Thread.current.to_s))
          i += 1
          sleep(0.001)
        end
      }
    end

    snapshot = Thread.new {
      while going
        madeleine.take_snapshot
        sleep(0.1)
      end
    }

    sleep(1)
    going = false
    madeleine.close

    madeleine2 = SnapshotMadeleine.new("LiveSnapshot")
    assert_equal(madeleine.system, madeleine2.system)
  end

  def prevalence_base
    "LiveSnapshot"
  end

  def teardown
    delete_directory(prevalence_base)
  end
end

class BatchedLogTest < Test::Unit::TestCase

  class MockMadeleine
    def initialize
      @lock = Sync.new
    end

    def execute_queued_transaction(transaction)
      transaction.execute(nil)
    end

    def lock
      return @lock
    end
  end

  class MockTransaction
    attr_reader :text

    def initialize(text)
      @text = text
    end

    def execute(system)
    end

    def ==(o)
      o.text == @text
    end
  end

  def setup
    @target = Madeleine::Batch::BatchedLog.new(".", MockMadeleine.new)
    @messages = []
  end

  def test_logging
    assert(File.stat(expected_file_name).file?)

    Madeleine::Batch::LogActor.launch(@target, 0.1)

    append("Hello")
    sleep(0.01)
    append("World")
    sleep(0.01)

    assert_equal(2, @target.queue_length)
    assert_equal(0, File.size(expected_file_name))

    sleep(0.2)

    assert_equal(0, @target.queue_length)
    file_size = File.size(expected_file_name)
    assert(file_size > 0)

    append("Again")
    sleep(0.2)

    assert_equal(3, @messages.size)
    assert(File.size(expected_file_name) > file_size)

    f = File.new(expected_file_name)

    @messages.each do |message|
      assert_equal(message, Marshal.load(f))
    end

    f.close
  end

  def append(text)
    Thread.new { 
      message = MockTransaction.new(text)
      @messages << message
      @target.store(message)
    }
  end

  def expected_file_name
    "000000000000000000001.command_log"
  end

  def teardown
    @target.close
    File.delete(expected_file_name)
  end

end

def delete_directory(directory_name)
  Dir.foreach(directory_name) do |file|
    next if file == "."
    next if file == ".."
    assert(File.delete(directory_name + File::SEPARATOR + file) == 1,
                                                                 "Unable to delete #{file}")
  end
  Dir.delete(directory_name)
end

def add_batched_tests(suite)
  suite << BatchedSnapshotMadeleineTest.suite
  suite << BatchedLogTest.suite
end

if __FILE__ == $0
  suite = Test::Unit::TestSuite.new("BatchedLogTest")
  add_batched_tests(suite)

  require 'test/unit/ui/console/testrunner'
  Thread.abort_on_exception = true
  Test::Unit::UI::Console::TestRunner.run(suite)
end
