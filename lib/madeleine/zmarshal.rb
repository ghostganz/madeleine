#
# Author::    Anders Bengtsson <ndrsbngtssn@yahoo.se>
# Copyright:: Copyright (c) 2004
#

require 'zlib'

module Madeleine
  #
  # Snapshot marshaller for compressed snapshots.
  #
  # Compresses the snapshots created by another marshaller. Uses either
  # Marshal (the default) or another supplied marshaller.
  #
  # Uses <tt>zlib</tt> to do on-the-fly compression/decompression.
  #
  # ZMarshal works with Ruby's own Marshal and YAML
  #
  # Usage:
  #
  #  require 'madeleine'
  #  require 'madeleine/zmarshal'
  #
  #  marshaller = Madeleine::ZMarshal.new(YAML)
  #  madeleine = SnapshotMadeleine.new("my_example_storage", marshaller) {
  #    SomeExampleApplication.new
  #  }
  #
  class ZMarshal

    def initialize(marshaller=Marshal)
      @marshaller = marshaller
    end

    def load(stream)
      zstream = Zlib::GzipReader.new(stream)
      begin
        return @marshaller.load(zstream)
      ensure
        zstream.finish
      end
    end

    def dump(system, stream)
      zstream = Zlib::GzipWriter.new(stream)
      begin
        @marshaller.dump(system, zstream)
      ensure
        zstream.finish
      end
      nil
    end
  end
end
