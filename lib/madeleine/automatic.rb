module Madeleine

# Automatic commands for Madeleine
#
# Author::    Stephen Sykes <ruby@stephensykes.com>
# Copyright:: Copyright (C) 2003-2004
# Version::   0.3
#
# This module provides a way of automatically generating command objects for madeleine to
# store.  It works by making a proxy object for all objects of any classes in which it is included.
# Method calls to these objects are intercepted, and stored as a command before being
# passed on to the real receiver.
#
# There is also a mechanism for specifying which methods not to intercept calls to by using
# automatic_read_only, and its opposite automatic_read_write.
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
            Prox.new(_old_new(*args, &block))
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
# Note: The command also records which system it belongs to.  This is used in a recovery situation.
# If a command contains a sysid that doesn't match the system sent to us, then we change that
# system's id to the one in the command.  This makes a system adopt the correct id as soon as a
# command for it is executed.  This is the case when restoring a system for which there is no snapshot.
#
    class Command
      def initialize(symbol, myid, sysid, *args)
        @symbol = symbol
        @myid = myid
        @sysid = sysid
        @args = args
      end
#
# Called by madeleine when the command is done either first time, or when restoring the log
#
      def execute(system)
        AutomaticSnapshotMadeleine.register_sysid(@sysid) if (system.sysid != @sysid)
        Thread.current[:system].myid2ref(@myid).thing.send(@symbol, *@args)
      end
    end
#
# This is a little class to pass to SnapshotMadeleine.  This is used for snapshots only. 
# It acts as the marshaller, and just passes marshalling requests on to the user specified
# marshaller.  This defaults to Marshal, but could be YAML or another.
# After we have done a restore, the ObjectSpace is searched for instances of Prox to
# add new objects to the list in AutomaticSnapshotMadeleine
#
    class Automatic_marshaller
      def Automatic_marshaller.load(arg)
        restored_obj = Thread.current[:system].marshaller.load(arg)
        ObjectSpace.each_object(Prox) {|o| Thread.current[:system].restore(o) if (o.sysid == restored_obj.sysid)}
        restored_obj
      end
      def Automatic_marshaller.dump(obj, stream = nil)
        Thread.current[:system].marshaller.dump(obj, stream)
      end
    end
#
# A Prox object is generated and returned by Interceptor each time a system object is created.
#
    class Prox
      attr_accessor :thing, :myid, :sysid
      
      def initialize(thing)
        if (thing)
          raise "App object created outside of app" unless Thread.current[:system]
          @sysid = Thread.current[:system].sysid
          @myid = Thread.current[:system].add(self)
          @thing = thing
        end
      end
#
# This automatically makes and executes a new Command if a method is called from 
# outside the system.
#
      def method_missing(symbol, *args, &block)
#      print "Sending #{symbol} to #{@thing.to_s}, myid=#{@myid}, sysid=#{@sysid}\n"
        raise NoMethodError, "Undefined method" unless @thing.respond_to?(symbol)
        if (Thread.current[:system] || @thing.read_only_methods.include?(symbol))
          @thing.send(symbol, *args, &block)
        else
          raise "Cannot make command with block" if block_given?
          Thread.current[:system] = AutomaticSnapshotMadeleine.systems[@sysid]
          begin
            result = Thread.current[:system].execute_command(Command.new(symbol, @myid, @sysid, *args))
          ensure
            Thread.current[:system] = false
          end
          result
        end
      end
#
# Custom marshalling - this adds the internal id (myid) and the system id to a marshall 
# of the object we are the proxy for.
# We take care to not marshal the same object twice, so circular references will work.
#
      def _dump(depth)
        if (Thread.current[:snapshot_memory])
          if (Thread.current[:snapshot_memory][self])
            [@myid.to_s, @sysid].pack("A8A30")
          else
            Thread.current[:snapshot_memory][self] = true
            [@myid.to_s, @sysid].pack("A8A30") + Thread.current[:system].marshaller.dump(@thing, depth)
          end
        else
          [@myid.to_s, @sysid].pack("A8A30")
        end
      end
#
# Custom marshalling - restore a Prox object.
#
      def Prox._load(str)
        x = Prox.new(nil)
        a = str.unpack("A8A30a*")
        x.myid = a[0].to_i
        x.sysid = a[1]
        x = Thread.current[:system].restore(x)
        x.thing = Thread.current[:system].marshaller.load(a[2]) if (a[2] > "")
        x
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
      attr_accessor :sysid
      attr_reader :list, :marshaller

      def initialize(directory_name, marshaller=Marshal, persister=SnapshotMadeleine, &new_system_block)
        @sysid ||= Time.now.to_f.to_s + Thread.current.object_id.to_s # Gererate a new sysid
        @myid_count = 0                                               # This sysid will be used only if new
        @list = {}                                                    # object is taken by madeleine
        Thread.current[:system] = self # during system startup system should not create commands
        AutomaticSnapshotMadeleine.register_sysid(@sysid) # this sysid may be overridden
        @marshaller = marshaller # until attrb
        begin
          @persister = persister.new(directory_name, Automatic_marshaller, &new_system_block)
          AutomaticSnapshotMadeleine.register_sysid(@sysid) # needed if there were no commands
        ensure
          Thread.current[:system] = false
        end
      end
#
# Add a proxy object to the list, return the myid for that object
#
      def add(proxo)  
        @list[@myid_count += 1] = proxo.object_id
        @myid_count
      end
#
# Restore a marshalled proxy object to list - myid_count is increased as required.
# If the object already exists in the system then the existing object must be used.
#
      def restore(proxo)  
        if (@list[proxo.myid] && proxo.sysid == myid2ref(proxo.myid).sysid) 
          proxo = myid2ref(proxo.myid)
        else
          @list[proxo.myid] = proxo.object_id
          @myid_count = proxo.myid if (@myid_count < proxo.myid)
        end
        @sysid = proxo.sysid # to be sure to have the correct sysid
        proxo
      end
#
# Returns a reference to the object indicated by the internal id supplied.
#
      def myid2ref(myid)
        raise "Internal id #{myid} not found" unless objid = @list[myid]
        ObjectSpace._id2ref(objid)
      end
#
# Take a snapshot of the system.
#
      def take_snapshot
        begin
          Thread.current[:system] = self
          Thread.current[:snapshot_memory] = {}
          @persister.take_snapshot
        ensure
          Thread.current[:snapshot_memory] = nil
          Thread.current[:system] = false
        end
      end
#
# Sets the real sid for this thread's system - called during startup or from a command.
#
      def AutomaticSnapshotMadeleine.register_sysid(sid)
        Thread.critical = true
        @@systems ||= {}  # holds systems by sysid
        @@systems[sid] = Thread.current[:system]
        Thread.critical = false
        @@systems[sid].sysid = sid
        @@systems[sid].list.delete_if {|k,v|  # set all the prox objects that already exist to have the right sysid
          begin
            ObjectSpace._id2ref(v).sysid = sid
            false
          rescue RangeError
            true # Id was to a GC'd object, delete it
          end
        }
      end
#
# Returns the hash containing the systems. 
#
      def AutomaticSnapshotMadeleine.systems
        @@systems
      end
#
# Pass on any other calls to the persister
#
      def method_missing(symbol, *args, &block)
        @persister.send(symbol, *args, &block)
      end
    end

  end
end

AutomaticSnapshotMadeleine = Madeleine::Automatic::AutomaticSnapshotMadeleine
