require 'madeleine/deserialize'
require 'madeleine/upgrade_snapshot'

module Madeleine

# Automatic commands for Madeleine
#
# Author::    Stephen Sykes <sds@stephensykes.com>
# Copyright:: Copyright (C) 2003-2004
# Version::   0.5
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
# will try to automatically detect and read either Marshal, YAML, SOAP, or compressed Marshal or YAML.
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
# It does this by returning an Automatic_proxy object that is a proxy for the real object.
#
# It also handles automatic_read_only and automatic_read_write, allowing user specification of which methods
# should be made into commands
#
    module Interceptor
#
# When included, redefine new so that we can return a proxy object instead, and define methods to handle
# keeping track of which methods are read only
#
      def self.included(klass)
        class <<klass #:nodoc:
          alias_method :_old_new, :new

          def new(*args, &block)
            Automatic_proxy.new(_old_new(*args, &block))
          end
#
# Called when a method added - remember symbol if read only 
#
          def method_added(symbol)
            self.instance_eval {
              @read_only_methods ||= []
              @auto_read_only_flag ||= false
              @read_only_methods << symbol if @auto_read_only_flag
              c = self
              while (c = c.superclass)
                @read_only_methods |= c.instance_eval {@read_only_methods} if c.instance_eval {instance_variables.include? "@read_only_methods"}
              end
            }
          end
#
# Set the read only flag, or add read only methods
#
          def automatic_read_only(*list)
            if (list == [])
              self.instance_eval {@auto_read_only_flag = true}
            else
              list.each {|s| self.instance_eval {@read_only_methods ||= []; @read_only_methods << s}}
            end
          end
#
# Clear the read only flag, or remove read only methods
#
          def automatic_read_write(*list)
            if (list == [])
              self.instance_eval {@auto_read_only_flag = false}
            else
              list.each {|s| self.instance_eval {@read_only_methods ||= []; @read_only_methods.delete(s)}}
            end
          end

        end
      end
#
# Return the list of read only methods so Automatic_proxy#method_missing can find what to and what not to make into a command
#
      def read_only_methods
        self.class.instance_eval {@read_only_methods}
      end
#
# You cannot pass self to other objects, need to pass a proxy.  You can use this method to get one.
#
      def proxy
        Automatic_proxy.new(self)
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
        if (@args.size == 1)  # because can't use (*args) syntax for attribute setters - who knows why
          eval "@target.#{@symbol.to_s} @args[0]"
        else
          eval "@target.#{@symbol.to_s}(*@args)"
        end
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
        Thread.current[:system].automatic_objects.root_proxy
      end
      def Automatic_marshaller.dump(obj, io = nil)
        Thread.current[:system].marshaller.dump(Thread.current[:system].automatic_objects, io)
      end
    end
#
# A proxy object is generated and returned by Interceptor each time a system object is created.
#
    class Automatic_proxy #:nodoc:
      def initialize(client_object)
        raise "App object created outside of app" unless Thread.current[:system]
        @sysid = Thread.current[:system].automatic_objects.sysid
        @myid = Thread.current[:system].automatic_objects.add(client_object)
      end
      def automatic_client_object
        AutomaticSnapshotMadeleine.systems[@sysid].automatic_objects.client_objects[@myid]
      end
#
# This automatically makes and executes a new Command if a method is called from 
# outside the system.
#
      def method_missing(symbol, *args, &block)
        cursys = Thread.current[:system]
        if (cursys)
          cursys.add_system(@sysid)
          @sysid = cursys.automatic_objects.sysid
        end
        thing = automatic_client_object
#      print "Sending #{symbol} to #{thing.to_s}, myid=#{@myid}, sysid=#{@sysid}\n"
        raise NoMethodError, "Undefined method" unless thing.respond_to?(symbol)
        if (cursys)
          thing.send(symbol, *args, &block)  # safe to use send after respond_to check
        else
          raise "Cannot make command with block" if block_given?
          begin
            Thread.current[:system] = AutomaticSnapshotMadeleine.systems[@sysid]
            if (thing.read_only_methods.include?(symbol))
              result = Thread.current[:system].execute_query(Command.new(symbol, self, *args))
            else
              result = Thread.current[:system].execute_command(Command.new(symbol, self, *args))
            end
          ensure
            Thread.current[:system] = false
          end
          result
        end
      end
#
# == is overridden so that you can compare your own objects.  This is because there may be more than one
# Automatic_proxy object that refers to the same client object.
#
      def ==(other)
        if (other.respond_to? :automatic_client_object)
          automatic_client_object == other.automatic_client_object
        else
          automatic_client_object == other
        end
      end
    end

#
# Automatic_objects takes care of all the items that need to be marshalled at snapshot time
#
    class Automatic_objects #:nodoc:
      attr_accessor :root_proxy
      attr_reader :sysid, :client_objects
      def initialize
        @sysid = Time.now.to_f.to_s + Thread.current.object_id.to_s # Gererate a new sysid
        @client_objects = []
      end
#
# Add a client object to the list, return the myid for that object
#
      def add(client_object)
        @client_objects << client_object unless (@client_objects.include? client_object)
        @client_objects.index client_object
     end
    end
#
# The AutomaticSnapshotMadeleine class contains an instance of the persister
# (default is SnapshotMadeleine) and provides additional automatic functionality.
#
# The class is instantiated the same way as SnapshotMadeleine:
# madeleine_sys = AutomaticSnapshotMadeleine.new("storage_directory") { A.new(param1, ...) }
# The second initialisation parameter is the persister.  Supported persisters are:
#
# * Marshal  (default)
# * YAML
# * SOAP::Marshal
# * Madeleine::ZMarshal.new(Marshal)
# * Madeleine::ZMarshal.new(YAML)
# * Madeleine::ZMarshal.new(SOAP::Marshal)
#
# The class keeps a record of all the systems that currently exist.
# Each instance of the class keeps a record of Automatic_proxy objects in that system.
#
# We also add functionality to take_snapshot in order to set things up so that the custom 
# marshalling will work correctly.
#
    class AutomaticSnapshotMadeleine
      attr_accessor :marshaller, :automatic_objects

      def initialize(directory_name, marshaller=Marshal, persister=SnapshotMadeleine, &new_system_block)
        @automatic_objects = Automatic_objects.new
        @marshaller = marshaller
        begin
          Thread.current[:system] = self # during system startup system should not create commands
          add_system
          @persister = persister.new(directory_name, Automatic_marshaller, &new_system_block)
          @automatic_objects.root_proxy = @persister.system
        rescue ArgumentError  # attempt to upgrade
          if (!@upgraded && CommandLog.log_file_names(directory_name, FileService.new).size == 0)
            upgradesys = AutomaticSnapshotMadeleine_upgrader.new(directory_name, marshaller, persister, &new_system_block)
            upgradesys.take_snapshot
            upgradesys.close
            @upgraded = true
            retry
          else
            raise
          end
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
      def AutomaticSnapshotMadeleine.systems  #:nodoc:
        @@systems
      end
#
# Add this system to the systems
#
      def add_system(sysid = automatic_objects.sysid)  #:nodoc:
        Thread.critical = true
        @@systems ||= {}  # holds systems by sysid
        Thread.critical = false
        @@systems[sysid] = self
      end
#
# Pass on any other calls to the persister
#
      def method_missing(symbol, *args, &block)  #:nodoc:
        raise NoMethodError, "Undefined method" unless @persister.respond_to?(symbol)
        @persister.send(symbol, *args, &block)
      end
    end

  end
end

AutomaticSnapshotMadeleine = Madeleine::Automatic::AutomaticSnapshotMadeleine
