#
# Automatic commands for Madeleine
#
# This is EXPERIMENTAL
#
# Copyright(c) Stephen Sykes 2003
# Version 0.11
#
# Usage:
# class A
#   include Madeleine::Automatic::Interceptor
#   def initialize(param1, ...)
#   ...
#   def some_method(paramA, ...)
#   ...
# end
# mad = Madeleine::Automatic::AutomaticSnapshotMadeleine.new("storage_directory") { A.new(param1, ...) }
# mad.system.some_method(paramA, ...)
# mad.take_snapshot
#

require 'singleton'

module Madeleine
  module Automatic

    module Interceptor
      class <<self
        def included(klass)
          class <<klass
            alias_method :_old_new, :new
            def new(*args, &block)
              Prox.new(_old_new(*args, &block))
            end
          end
        end
      end
    end
#
# Command object
# A passed block cannot be serialized, so that bit won't work
#
# Note: if a command contains a sysid that doesn't match the system sent to us, then we change that
# system's id to the one in the command.  This makes a system adopt the correct id as soon as a
# command for it is executed.  This is the case when restoring a system for which there is no snapshot.
#
    class Command
      def initialize(symbol, myid, sysid, *args, &block)
        @symbol = symbol
        @myid = myid
        @sysid = sysid
        @args = args
        @block = block
      end

      def execute(system)
        System.instance.register_sysid(@sysid) if (system.sysid != @sysid)
        Thread.current[:syscont].listid2ref(@myid).thing.send(@symbol, *@args, &@block)
      end
    end
#
# Proxy class
# All classes in the persistence are represented by these
#
    class Prox
      attr_accessor :thing, :myid, :sysid
      
      def initialize(x)
        if (x) 
          raise "App object created outside of app" unless Thread.current[:syscont]
          @sysid = Thread.current[:syscont].sysid
          @myid = Thread.current[:syscont].add(self)
          @thing = x
        end
      end

      def method_missing(symbol, *args, &block)
#      print "Sending #{symbol} to #{@thing.to_s}, myid=#{@myid}, sysid=#{@sysid}\n"
        raise NoMethodError, "Undefined method" unless @thing.respond_to?(symbol)
        if (Thread.current[:syscont])
          @thing.send(symbol, *args, &block)
        else
          Thread.current[:syscont] = System.instance.syscontainers[@sysid]
          begin
            x = Thread.current[:syscont].execute_command(Command.new(symbol, @myid, @sysid, *args, &block))
          ensure
            Thread.current[:syscont] = false
          end
          x
        end
      end
    
      def _dump(depth)
        if (Thread.current[:taking_snapshot])
          [@myid.to_s, @sysid].pack("A8A30") + Thread.current[:syscont].marshaller.dump(@thing, depth)
        else
          [@myid.to_s, @sysid].pack("A8A30")
        end
      end
      
      def Prox._load(str)
        x = Prox.new(nil)
        a = str.unpack("A8A30a*")
        x.myid = a[0].to_i
        x.sysid = a[1]
        x.thing = Thread.current[:syscont].marshaller.load(a[2]) if (a[2] > "")
        Thread.current[:syscont].restore(x)
      end
    end

#
# AutomaticSnapshotMadeleine class
# Keeps a record of Prox objects by internal id for a system
#
    class AutomaticSnapshotMadeleine < SnapshotMadeleine
      attr_accessor :sysid
      attr_reader :list, :marshaller
      
      def initialize(directory_name, marshaller=nil, &new_system_block)
        @sysid ||= Time.now.to_f.to_s + Thread.current.object_id.to_s # Gererate a new sysid
        @obj_count = 0                                         # This sysid will be used only if new object is 
        @list = {}                                             # taken by madeleine
        Thread.current[:syscont] = self   # also ensures that no commands are generated during restore
        System.instance.register_sysid(@sysid)   # this sysid may be overridden, but need to record it anyway
        begin
          if marshaller.nil?
            super(directory_name, &new_system_block)
          else
            super(directory_name, marshaller, &new_system_block)
          end
          System.instance.register_sysid(@sysid)  # needed if there were no commands
        ensure
          Thread.current[:syscont] = false
        end
      end

      def add(proxo)  # add a proxy object to the list
        @list[@obj_count += 1] = proxo.object_id
        @obj_count
      end
      
      def restore(proxo)  # restore a marshalled proxy object to list - obj_count is increased as required
        if (@list[proxo.myid] && proxo.sysid == listid2ref(proxo.myid).sysid) # if we already have this system's object, use that
          proxo = listid2ref(proxo.myid)
        else
          @list[proxo.myid] = proxo.object_id
          @obj_count = proxo.myid if (@obj_count < proxo.myid)
        end
        @sysid = proxo.sysid # to be sure to have the correct sysid in the container
        proxo
      end
      
      def listid2ref(lid)
        raise "Internal id #{lid} not found" unless x = @list[lid]
        ObjectSpace._id2ref(x)
      end

      def take_snapshot
        begin
          Thread.current[:syscont] = self
          Thread.current[:taking_snapshot] = true
          super
        ensure
          Thread.current[:taking_snapshot] = false
          Thread.current[:syscont] = false
        end
      end

    end
#
# System
# This is a singleton class that keeps track of syscontainers
#
    class System
      include Singleton
      attr_reader :syscontainers

      def register_sysid(sid)  # sets the real sid for this thread's container - during startup or from a command
        @syscontainers ||= {}  # holds syscontainers by sysid
        @syscontainers[sid] = Thread.current[:syscont]
        @syscontainers[sid].sysid = sid 
        @syscontainers[sid].list.each {|o|  # set all the prox objects that already exist to have the right sysid
                         ObjectSpace._id2ref(o[1]).sysid = sid
                       }
      end
    end
  end
end
