#
# Copyright(c) Anders Bengtsson 2004
#

require 'zlib'

module Madeleine
  module ZMarshal

    def self.load(stream)
      zstream = Zlib::GzipReader.new(stream)
      begin
        return Marshal.load(zstream)
      ensure
        zstream.finish
      end
    end

    def self.dump(system, stream)
      zstream = Zlib::GzipWriter.new(stream)
      begin
        Marshal.dump(system, zstream)
      ensure
        zstream.finish
      end
      nil
    end
  end
end

ZMarshal = Madeleine::ZMarshal
