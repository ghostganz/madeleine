#
# Copyright(c) Anders Bengtsson 2004
#

require 'zlib'

module Madeleine
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

ZMarshal = Madeleine::ZMarshal
