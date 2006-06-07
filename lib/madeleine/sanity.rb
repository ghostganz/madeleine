#
# Author::    Anders Bengtsson <ndrsbngtssn@yahoo.se>
# Copyright:: Copyright (c) 2004-2006
#

require 'tempfile'
require 'singleton'

module Madeleine
  class SanityCheck
    include Singleton

    def initialize
      @testdata = "\x85\x00\x0a\0x0d\x0a".freeze
      @was_run = false
    end

    def run_once
      unless @was_run
        run
      end
    end

    def run
      marshal_check
      file_check
      @was_run = true
    end

    def marshal_check
      result = Marshal.load(Marshal.dump(@testdata))
      if result != @testdata
        raise "Sanity check failed for Marshal"
      end
    end

    def file_check
      Tempfile.open("madeleine_sanity") do |file|
        file.binmode  # Needed for win32
        file.write(@testdata)
        file.flush
        open(file.path, 'rb') do |read_file|
          result = read_file.read
          if result != @testdata
            raise "Sanity check failed for file IO"
          end
        end
      end
    end
  end
end
