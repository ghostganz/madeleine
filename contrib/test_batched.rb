#!/usr/local/bin/ruby -w
#
# Copyright(c) 2003 H�kan R�berg
#
# Some components taken from test_persistence.rb
# Copyright(c) 2003 Anders Bengtsson
#

$LOAD_PATH.unshift("../lib")

require 'batched'
require 'test/unit'
require 'madeleine/clock'


module Madeleine::Batch
  class BatchedSnapshotMadeleineTest < Test::Unit::TestCase

    class ArraySystem < Array
      include Madeleine::Clock::ClockedSystem
    end

    class PushTransaction
      def initialize(value)
        @value = value
      end

      def execute(system)
        system << @value
      end
    end 

    class ArrayQueryTransaction
      def execute(system)
        length = system.length      
        time = system.clock.time

        a = 1
        system.each do |n|
          a *= n
        end      

        raise "inconsistent read" unless length == system.length
        raise "inconsistent read" unless time == system.clock.time
      end
    end

    def test_live_snapshot
      system = ArraySystem.new
      w, r = [], []
      going = true

      madeleine = BatchedSnapshotMadeleine.new(prevalence_base) { system }

      i = 0
      10.times do |n| 
        w[n] = Thread.new {
          while going
            madeleine.execute_command(PushTransaction.new(i))
            i += 1
            sleep(0.1)
          end
        }
      end

      q = 0
      query = ArrayQueryTransaction.new
      100.times do |n| 
        r[n] = Thread.new {
          while going
            begin
              madeleine.execute_query(query)
              q += 1
            rescue
              fail("Query blocks writing")
            end
            sleep(0.1)
          end
        }
      end

      snapshot = Thread.new {
        while going
          madeleine.take_snapshot
          sleep(0.01)
        end
      }

      sleep(1)

      going = false

      r.each do |t|
        t.join
      end

      w.each do |t|
        t.join
      end

      snapshot.join

      madeleine.close

      madeleine2 = SnapshotMadeleine.new("LiveSnapshot")
      assert_equal(madeleine.system, madeleine2.system,  "Take system snapshots while accessing")
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
      def initialize(logger)
        @lock = MockSync.new
        @logger = logger
      end

      def execute_queued_transaction(transaction)
        transaction.execute(nil)
      end

      def flush
        @logger.flush(lock)
      end

      def lock
        return @lock
      end
    end

    class MockSync
      def synchronize
        yield
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

    module BufferInspector
      def buffer_size
        @buffer.size
      end
    end

    def setup
      @target = BatchedLogger.new(".", BatchedLogFactory.new, nil)
      @target.extend(BufferInspector)
      @madeleine = MockMadeleine.new(@target)
      @messages = []
    end

    def test_logging
      actor = LogActor.launch(@madeleine, 0.1)
      
      append("Hello")
      sleep(0.01)
      append("World")
      sleep(0.01)

      assert_equal(2, @target.buffer_size, "Batched transaction queue")
      assert(!File.exist?(expected_file_name), "Batched transactions not on disk")

      sleep(0.2)

      assert_equal(0, @target.buffer_size, "Queue emptied by batched write")
      file_size = File.size(expected_file_name)
      assert(file_size > 0, "Queue written to disk")

      append("Again")
      sleep(0.2)

      assert(File.size(expected_file_name) > file_size, "Transaction written to disk")

      f = File.new(expected_file_name)

      @messages.each do |message|
        assert_equal(message, Marshal.load(f), "Transactions logged in order")
      end

      f.close

      actor.destroy
      @target.flush(@madeleine.lock)
      @target.close

    end

    def append(text)
      Thread.new { 
        message = MockTransaction.new(text)
        @messages << message
        transaction = QueuedTransaction.new(message)
        @target.store(transaction)
        transaction.wait_for
      }
    end

    def expected_file_name
      "000000000000000000001.command_log"
    end

    def teardown
      assert(File.delete(expected_file_name) == 1)
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
end

 include Madeleine::Batch

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
