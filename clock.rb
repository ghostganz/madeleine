#
# Copyright(c) Anders Bengtsson 2003
#

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

      class << self
        def launch(prevayler, delay=1.0)
          result = new(prevayler, delay)
          result
        end
      end

      def destroy
        @is_destroyed = true
        @thread.wakeup
      end

      private

      def initialize(prevayler, delay)
        @prevayler = prevayler
        @is_destroyed = false
        launch(delay)
      end

      def launch(delay)
        @thread = Thread.new {
          until @is_destroyed
            @prevayler.execute_command(Tick.new(Time.now))
            sleep(delay)
          end
        }
      end
    end

    #
    # Internal classes below
    #

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
