#
# Copyright(c) Anders Bengtsson 2003
#

require 'madeleine'

module Madeleine
  module Clock

    class ClockedSystem

      def initialize
        @clock = Clock.new
      end

      def time
        @clock.time
      end

      def forward_clock_to(newTime)
        @clock.forward_to(newTime)
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
        @received_first_tick = false
      end

      def store(command)
        if command.kind_of?(Tick)
          @received_first_tick = true
          @pending_tick = command
        else
          if ! @received_first_tick
            raise "Can't log command - no clock tick received yet"
          end
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
