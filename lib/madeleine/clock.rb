#
# Copyright(c) Anders Bengtsson 2003
#

require 'madeleine'

module Madeleine
  module Clock

    class ClockedSnapshotMadeleine < SnapshotMadeleine

      def initialize(new_system, directory_name)
        super(new_system, directory_name)
      end

      def log_factory
        TimeOptimizingCommandLogFactory.new
      end
    end

    module ClockedSystem

      def time
        verify_clock_initialized
        clock.time
      end

      def forward_clock_to(newTime)
        clock.forward_to(newTime)
      end

      def clock
        unless defined? @clock
          @clock = Clock.new
        end
        @clock
      end

      def verify_clock_initialized
        unless defined? @clock
          raise "Trying to get time before clock initialized"
        end
      end
    end

    class TimeActor

      def self.launch(madeleine, delay=0.1)
        result = new(madeleine, delay)
        result
      end

      def destroy
        @is_destroyed = true
        @thread.wakeup
        @thread.join
      end

      private

      def initialize(madeleine, delay)
        @madeleine = madeleine
        @is_destroyed = false
        send_tick
        @thread = Thread.new {
          until @is_destroyed
            sleep(delay)
            send_tick
          end
        }
      end

      def send_tick
        @madeleine.execute_command(Tick.new(Time.now))
      end
    end

    class TimeOptimizingCommandLogFactory
      def create_log(directory_name)
        TimeOptimizingCommandLog.new(directory_name)
      end
    end

    #
    # Internal classes below
    #

    class TimeOptimizingCommandLog < CommandLog

      def initialize(path)
        super(path)
        @pending_tick = nil
      end

      def store(command)
        if command.kind_of?(Tick)
          @pending_tick = command
        else
          if @pending_tick
            super(@pending_tick)
            @pending_tick = nil
          end
          super(command)
        end
      end
    end

    class Clock
      attr_reader :time

      def initialize
        @time = Time.at(0)
      end

      def forward_to(newTime)
        if newTime < @time
          raise "Can't decrease clock's time."
        end
        @time = newTime
      end
    end

    class Tick

      def initialize(time)
        @time = time
      end

      def execute(system)
        system.forward_clock_to(@time)
      end
    end

  end
end
