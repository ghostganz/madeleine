# Batched writes for Madeleine
#
# Copyright(c) Håkan Råberg 2003
#
# 
# This is an experimental implementation of batched log writes to mininize 
# calls to fsync. It uses a Shared/Exclusive-Lock, implemented in sync.rb, 
# which is included in Ruby 1.8.
#
# Writes are batched for a specified amount of time, before written to disk and
# then executed. This 
#
# For a detailed discussion about the problem, see
#  http://www.prevayler.org/wiki.jsp?topic=OvercomingTheWriteBottleneck
#
#
# Usage is identical to normal SnapshotMadeleine, and it can also be used as
# persister for AutomaticSnapshotMadeleine.
#
#
# Madeleine - Ruby Object Prevalence
#
# Copyright(c) Anders Bengtsson 2003
#

require 'madeleine'
require 'madeleine/clock'

module Madeleine
  module Batch

    class BatchedSnapshotMadeleine < ClockedSnapshotMadeleine

      def execute_command(command)
        verify_command_sane(command)
        raise "closed" if @closed

        @lock.sync_synchronize(:SH) do
          @logger.store(command)
        end
      end

      def execute_queued_transaction(transaction)        
        execute_without_storing(transaction)
      end

      private

      def log_factory
        BatchedLogFactory.new(self)
      end
    end

    class BatchedLogFactory
      def initialize(madeleine)
        @madeleine = madeleine
      end

      def create_log(directory_name)
        log = BatchedLog.new(directory_name, @madeleine)
        LogActor.launch(log)
        log
      end
    end

    class LogActor
      def self.launch(log, delay=0.01)
        result = new(log, delay)
        result
      end

      def destroy
        @is_destroyed = true
        @thread.wakeup
        @thread.join
      end

      private

      def initialize(log, delay)
        @log = log
        @is_destroyed = false

        @log.flush
        @thread = Thread.new {
          until @is_destroyed or @log.closed
            sleep(delay)
            @log.flush
          end
        }
      end
    end

    class BatchedLog < Madeleine::CommandLog
      attr_reader :closed

      def initialize(path, madeleine)
        super(path)

        @madeleine = madeleine
        @buffer = []
        @lock = Mutex.new

        @closed = false
      end
      
      def close
        flush        
        @lock.synchronize do
          @closed = true 
          @file.close
        end
      end

      def store(command)
        raise "closed" if @closed

        transaction = QueuedTransaction.new(command)

        @lock.synchronize do
          @buffer << transaction
        end

        transaction.wait_for
      end

      def queue_length
        @lock.synchronize do
           @buffer.size
        end
      end

      def flush
        @lock.synchronize do
          return if @buffer.empty? or @closed

          @buffer.each do |transaction|
            transaction.dump(@file)
          end

          @file.flush
          @file.fsync
          
          @buffer.each do |transaction|
            @madeleine.execute_queued_transaction(transaction)
          end
          @buffer.clear
        end
      end
    end

    class QueuedTransaction
      attr_reader :command

      def initialize(command)
        @command = command

        @pipe = SimplisticPipe.new
      end

      def dump(file)
        @pipe.send(file)
      end

      def execute(system)
        @pipe.send(system)
      end

      def wait_for
        @pipe.receive do |file|        
          Marshal.dump(@command, file)
        end

        @pipe.receive do |system|
          return @command.execute(system)
        end
      end
    end

    class SimplisticPipe
      def initialize 
        @first = Mutex.new.lock 
        @second = Mutex.new.lock 
        @messages = [] 
      end

      def receive
        begin
          @first.lock
          yield @messages
          @messages
        ensure
          @messages = []
          @second.unlock
        end
      end

      def send(*messages)
        @messages = *messages
        @first.unlock
        @second.lock
        @second.lock if not @second.locked?
      end
    end

  end
end

BatchedSnapshotMadeleine = Madeleine::Batch::BatchedSnapshotMadeleine
