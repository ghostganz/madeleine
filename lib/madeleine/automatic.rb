require 'yaml'
require 'madeleine/zmarshal'

module Madeleine

# Automatic commands for Madeleine
#
# Author::    Stephen Sykes <ruby@stephensykes.com>
# Copyright:: Copyright (C) 2003-2004
# Version::   0.4
#
# This module provides a way of automatically generating command objects for madeleine to
# store.  It works by making a proxy object for all objects of any classes in which it is included.
# Method calls to these objects are intercepted, and stored as a command before being
# passed on to the real receiver.  The command objects remember which object the command was
# destined for by using a pair of internal ids that are contained in each of the proxy objects.
#
# There is also a mechanism for specifying which methods not to intercept calls to by using
# automatic_read_only, and its opposite automatic_read_write.
#
# Should you require it, the snapshots can be stored as yaml, and can be compressed.  Just pass 
# the marshaller you want to use as the second argument to AutomaticSnapshotMadeleine.new.  
# If the passed marshaller did not successfully deserialize the latest snapshot, the system 
# will try to automatically detect and read either Marshal, YAML, or compressed Marshal or YAML.
#
# This module is designed to work correctly in the case there are multiple madeleine systems in use by
# a single program, and is also safe to use with threads.
#
# Usage:
#
#  require 'madeleine'
#  require 'madeleine/automatic'
#
#  class A
#    include Madeleine::Automatic::Interceptor
#    attr_reader :foo
#    automatic_read_only :foo
#    def initialize(param1, ...)
#      ...
#    end
#    def some_method(paramA, ...)
#      ...
#    end
#    automatic_read_only
#    def bigfoo
#      foo.upcase
#    end
#  end
#
#  mad = AutomaticSnapshotMadeleine.new("storage_directory") { A.new(param1, ...) }
#
#  mad.system.some_method(paramA, ...) # logged as a command by madeleine
#  print mad.foo                       # not logged
#  print mad.bigfoo                    # not logged
#  mad.take_snapshot
#

  module Automatic
#
# This module should be included (at the top) in any classes that are to be persisted.
# It will intercept method calls and make sure they are converted into commands that are logged by Madeleine.
# It does this by returning a Prox object that is a proxy for the real object.
#
# It also handles automatic_read_only and automatic_read_write, allowing user specification of which methods
# should be made into commands
#
    module Interceptor
#
# When included, redefine new so that we can return a Prox object instead, and define methods to handle
# keeping track of which methods are read only
#
      def self.included(klass)
        class <<klass #:nodoc:
          alias_method :_old_new, :new
          @@auto_read_only_flag = false
          @@read_only_methods = []

          def new(*args, &block)
            Proxy_stub.new(_old_new(*args, &block))
          end
#
# Called when a method added - remember symbol if read only 
#
          def method_added(symbol)
            @@read_only_methods << symbol if @@auto_read_only_flag
          end
#
# Set the read only flag, or add read only methods
#
          def automatic_read_only(*list)
            if (list == [])
              @@auto_read_only_flag = true
            else
              list.each {|s| @@read_only_methods << s}
            end
          end
#
# Clear the read only flag, or remove read only methods
#
          def automatic_read_write(*list)
            if (list == [])
              @@auto_read_only_flag = false
            else
              list.each {|s| @@read_only_methods.delete(s)}
            end
          end

        end
      end
#
# Return the list of read only methods so Prox#method_missing can find what to and what not to make into a command
#
      def read_only_methods
        @@read_only_methods
      end
    end

#
# A Command object is automatically created for each method call to an object within the system that comes from without.
# These objects are recorded in the log by Madeleine.
# 
    class Command
      def initialize(symbol, target, *args)
        @symbol = symbol
        @target = target
        @args = args
      end
#
# Called by madeleine when the command is done either first time, or when restoring the log
#
      def execute(system)
        @target.send(@symbol, *@args)
      end
    end
#
# This is a little class to pass to SnapshotMadeleine.  This is used for snapshots only. 
# It acts as the marshaller, and just passes marshalling requests on to the user specified
# marshaller.  This defaults to Marshal, but could be YAML or another.
#
    class Automatic_marshaller #:nodoc:
      def Automatic_marshaller.load(io)
        Thread.current[:system].automatic_objects = Deserialize.load(io, Thread.current[:system].marshaller)
        Thread.current[:system].add_system
        Thread.current[:system].automatic_objects.root_stub
      end
      def Automatic_marshaller.dump(obj, io = nil)
        Thread.current[:system].marshaller.dump(Thread.current[:system].automatic_objects, io)
      end
    end
#
# A Prox object is generated and returned by Interceptor each time a system object is created.
#
    class Proxy_stub #:nodoc:
      def initialize(client_object)
        if (client_object)
          raise "App object created outside of app" unless Thread.current[:system]
          @sysid = Thread.current[:system].automatic_objects.sysid
          @myid = Thread.current[:system].automatic_objects.add(client_object)
        end
      end
#
# This automatically makes and executes a new Command if a method is called from 
# outside the system.
#
      def method_missing(symbol, *args, &block)
        if (Thread.current[:system])
          Thread.current[:system].add_system(@sysid)
          @sysid = Thread.current[:system].automatic_objects.sysid
        end
        thing = AutomaticSnapshotMadeleine.systems[@sysid].automatic_objects.client_objects[@myid]
#      print "Sending #{symbol} to #{thing.to_s}, myid=#{@myid}, sysid=#{@sysid}\n"
        raise NoMethodError, "Undefined method" unless thing.respond_to?(symbol)
        if (Thread.current[:system] || thing.read_only_methods.include?(symbol))
          thing.send(symbol, *args, &block)
        else
          raise "Cannot make command with block" if block_given?
          Thread.current[:system] = AutomaticSnapshotMadeleine.systems[@sysid]
          begin
            result = Thread.current[:system].execute_command(Command.new(symbol, self, *args))
          ensure
            Thread.current[:system] = false
          end
          result
        end
      end
    end

    class Automatic_objects #:nodoc:
      attr_accessor :root_stub
      attr_reader :sysid, :client_objects
      def initialize
        @sysid = Time.now.to_f.to_s + Thread.current.object_id.to_s # Gererate a new sysid
        @client_objects = []
      end
#
# Add a client object to the list, return the myid for that object
#
      def add(client_object)
        @client_objects << client_object
        @client_objects.size - 1
      end

    end
#
# The AutomaticSnapshotMadeleine class contains an instance of the persister
# (default is SnapshotMadeleine) and provides additional automatic functionality.
#
# The class keeps a record of all the systems that currently exist.
# Each instance of the class keeps a record of Prox objects in that system by internal id (myid).
#
# We also add functionality to take_snapshot in order to set things up so that the custom Prox object 
# marshalling will work correctly.
#
    class AutomaticSnapshotMadeleine
      attr_accessor :marshaller, :automatic_objects

      def initialize(directory_name, marshaller=Marshal, persister=SnapshotMadeleine, &new_system_block)
        @automatic_objects = Automatic_objects.new
        Thread.current[:system] = self # during system startup system should not create commands
        @marshaller = marshaller # until attrb
        add_system
        begin
          @persister = persister.new(directory_name, Automatic_marshaller, &new_system_block)
          @automatic_objects.root_stub = @persister.system
        ensure
          Thread.current[:system] = false
        end
      end
#
# Take a snapshot of the system.
#
      def take_snapshot
        begin
          Thread.current[:system] = self
          @persister.take_snapshot
        ensure
          Thread.current[:system] = false
        end
      end
#
# Returns the hash containing the systems. 
#
      def AutomaticSnapshotMadeleine.systems
        @@systems
      end
#
# Add this system to the systems
#
      def add_system(sysid = automatic_objects.sysid)
        Thread.critical = true
        @@systems ||= {}  # holds systems by sysid
        Thread.critical = false
        @@systems[sysid] = self
      end
#
# Pass on any other calls to the persister
#
      def method_missing(symbol, *args, &block)
        @persister.send(symbol, *args, &block)
      end
    end


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
              ZMarshal.new(detected_zmarshaller).load(io)
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

AutomaticSnapshotMadeleine = Madeleine::Automatic::AutomaticSnapshotMadeleine
