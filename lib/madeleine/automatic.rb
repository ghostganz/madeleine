#
# Automatic commands for Madeleine
#
# This is EXPERIMENTAL
#
# Copyright(c) Stephen Sykes 2003
# Version 0.17
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
#
# Note: if a command contains a sysid that doesn't match the system sent to us, then we change that
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

      def execute(system)
        AutomaticSnapshotMadeleine.register_sysid(@sysid) if (system.sysid != @sysid)
        Thread.current[:system].listid2ref(@myid).thing.send(@symbol, *@args)
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
          raise "App object created outside of app" unless Thread.current[:system]
          @sysid = Thread.current[:system].sysid
          @myid = Thread.current[:system].add(self)
          @thing = x
        end
      end

      def method_missing(symbol, *args, &block)
#      print "Sending #{symbol} to #{@thing.to_s}, myid=#{@myid}, sysid=#{@sysid}\n"
        raise NoMethodError, "Undefined method" unless @thing.respond_to?(symbol)
        if (Thread.current[:system])
          @thing.send(symbol, *args, &block)
        else
          raise "Cannot make command with block" if block_given?
          Thread.current[:system] = AutomaticSnapshotMadeleine.systems[@sysid]
          begin
            x = Thread.current[:system].execute_command(Command.new(symbol, @myid, @sysid, *args))
          ensure
            Thread.current[:system] = false
          end
          x
        end
      end
    
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
# AutomaticSnapshotMadeleine class - extends SnapshotMadeleine
# Keeps a record of Prox objects by internal id for a system
# Also has class methods that keep track of systems by sysid
#
    class AutomaticSnapshotMadeleine < SnapshotMadeleine
      attr_accessor :sysid
      attr_reader :list, :marshaller
      
      def initialize(directory_name, marshaller=nil, &new_system_block)
        @sysid ||= Time.now.to_f.to_s + Thread.current.object_id.to_s # Gererate a new sysid
        @obj_count = 0                                         # This sysid will be used only if new object is 
        @list = {}                                             # taken by madeleine
        Thread.current[:system] = self   # also ensures that no commands are generated during restore
        AutomaticSnapshotMadeleine.register_sysid(@sysid)   # this sysid may be overridden, but need to record it anyway
        begin
          if marshaller.nil?
            super(directory_name, &new_system_block)
          else
            super(directory_name, marshaller, &new_system_block)
          end
          AutomaticSnapshotMadeleine.register_sysid(@sysid)  # needed if there were no commands
        ensure
          Thread.current[:system] = false
        end
      end

      def add(proxo)  # add a proxy object to the list
        @list[@obj_count += 1] = proxo.object_id
        @obj_count
      end

      def restore(proxo)  # restore a marshalled proxy object to list - obj_count is increased as required
        # if we already have this system's object, use that
        if (@list[proxo.myid] && proxo.sysid == listid2ref(proxo.myid).sysid) 
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
          Thread.current[:system] = self
          Thread.current[:snapshot_memory] = {}
          super
        ensure
          Thread.current[:snapshot_memory] = nil
          Thread.current[:system] = false
        end
      end

# sets the real sid for this thread's system - during startup or from a command
      def AutomaticSnapshotMadeleine.register_sysid(sid)
        Thread.critical = true
        @@systems ||= {}  # holds systems by sysid
        @@systems[sid] = Thread.current[:system]
        Thread.critical = false
        @@systems[sid].sysid = sid 
        @@systems[sid].list.each {|o|  # set all the prox objects that already exist to have the right sysid
                         ObjectSpace._id2ref(o[1]).sysid = sid
                       }
      end

      def AutomaticSnapshotMadeleine.systems
        @@systems
      end

    end

  end
end
