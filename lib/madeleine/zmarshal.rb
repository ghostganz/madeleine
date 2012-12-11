#
# Author::    Anders Bengtsson <ndrsbngtssn@yahoo.se>
# Copyright:: Copyright (c) 2004-2012
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
      zstream = WorkaroundGzipReader.new(stream)
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

    private

    class WorkaroundGzipReader < Zlib::GzipReader
      # The 'psych' YAML parser, default since Ruby 1.9.3,
      # assumes that its input IO has an external_encoding()
      # method.
      unless defined? external_encoding
        def external_encoding
          nil
        end
      end
    end
  end
end
