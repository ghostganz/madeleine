require 'yaml'
require 'madeleine/zmarshal'
require 'soap/marshal'

module Madeleine
  module Automatic
#
# Tool for autodetecting and deserializing a file from multiple possible formats:
#
# * Marshal
# * YAML
# * SOAP::Marshal
# * Madeleine::ZMarshal.new(Marshal)
# * Madeleine::ZMarshal.new(YAML)
# * Madeleine::ZMarshal.new(SOAP::Marshal)
#
    module Deserialize #:nodoc:
#
# Detect format of an io stream. Leave it rewound.
#
      def Deserialize.detect(io)
        c = io.getc
        c1 = io.getc
        io.rewind
        if (c == Marshal::MAJOR_VERSION && c1 <= Marshal::MINOR_VERSION)
          Marshal
        elsif (c == 31 && c1 == 139) # gzip magic numbers
          ZMarshal
        else
          while (s = io.gets)
            break if (s !~ /^\s*$/) # ignore blank lines
          end
          io.rewind
          if (s && s =~ /^\s*<\?[xX][mM][lL]/) # "<?xml" begins an xml serialization
            SOAP::Marshal
          else
            while (s = io.gets)
              break if (s !~ /^\s*#/ && s !~ /^\s*$/) # ignore blank and comment lines
            end
            io.rewind
            if (s && s =~ /^\s*---/) # "---" is the yaml header
              YAML
            else
              nil # failed to detect
            end
          end
        end
      end
#
# Try to deserialize object.  If there was an error, try to detect marshal format, 
# and return deserialized object using the right marshaller
# If detection didn't work, raise up the exception
#
      def Deserialize.load(io, marshaller=Marshal)
        begin
          marshaller.load(io)
        rescue Exception => e
          io.rewind
          detected_marshaller = detect(io)
          if (detected_marshaller == ZMarshal)
            zio = Zlib::GzipReader.new(io)
            detected_zmarshaller = detect(zio)
            zio.finish
            io.rewind
            if (detected_zmarshaller)
              if (detected_zmarshaller == SOAP::Marshal)
                zio = Zlib::GzipReader.new(io)
                xml = zio.read
                zio.finish
                SOAP::Marshal.load(xml)
              else
                ZMarshal.new(detected_zmarshaller).load(io)
              end
            else
              raise e
            end
          elsif (detected_marshaller)
            detected_marshaller.load(io)
          else
            raise e
          end
        end
      end
    end
  end  
end
