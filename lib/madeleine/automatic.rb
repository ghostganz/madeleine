#
# Automatic commands for Madeleine
#
# This is EXPERIMENTAL
#
# Copyright(c) Stephen Sykes 2003
# Version 0.1
#
# Usage:
# class A
#   include Madeleine::Automatic::Interceptor
#   def initialize(param1, ...)
#   ...
#   def some_method(paramA, ...)
#   ...
# end
# mad = Madeleine::Automatic::System.start("storage_directory", A, param1, ...)
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
        System.instance.thread2sys.listid2ref(@myid).thing.send(@symbol, *@args, &@block)
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
          @sysid = System.instance.thread2sys.sysid
          @myid = System.instance.thread2sys.add(self)
          @thing = x
        end
      end

      def method_missing(symbol, *args, &block)
#      print "Sending #{symbol} to #{@thing.to_s}, myid=#{@myid}, sysid=#{@sysid}\n"
        Thread.current[:sysid] = @sysid
        if (Thread.current[:in_command])
          @thing.send(symbol, *args, &block)
        else
          Thread.current[:in_command] = true
          begin
            x = System.instance.thread2sys.madeleineSys.execute_command(Command.new(symbol, @myid, 
                                                                                    @sysid, *args, &block))
          ensure
            Thread.current[:in_command] = false
          end
          x
        end
      end
    
      def _dump(depth)
        [@myid.to_s, @sysid].pack("A7A30") +  Marshal.dump(@thing)
      end
      
      def Prox._load(str)
        x = Prox.new(nil)
        a = str.unpack("A7A30a*")
        x.myid = a[0].to_i
        x.sysid = a[1]
        x.thing = Marshal.load(a[2])
        System.instance.thread2sys.restore(x)
      end
    end
#
# Syscontainer class
# Keeps a record of Prox objects by internal id for a system
#
    class SysContainer
      attr_accessor :sysid, :list, :obj_count
      attr_reader :madeleineSys
      
      def initialize
        @sysid ||= Time.now.to_f.to_s + Thread.current.id.to_s # Gererate a new sysid
        @obj_count = 0                                         # This sysid will be used only if new object is 
        @list = {}                                             # taken by madeleine
      end
      
      def startMadeleine(directory_name, klass, *init_args)
        Thread.current[:sysid] = @sysid     # might be changed if a different id is found in a command
        Thread.current[:in_command] = true  # so that no commands are generated during restore
        begin
          @madeleineSys = Madeleine::SnapshotMadeleine.new(directory_name) { klass.new(*init_args) }
        ensure
          Thread.current[:in_command] = false
        end
        @madeleineSys
      end
      
      def add(proxo)  # add a proxy object to the list
        @list[@obj_count += 1] = proxo.id
        @obj_count
      end
      
      def restore(proxo)  # restore a marshalled proxy object to list - obj_count is increased as required
        if (@list[proxo.myid] && proxo.sysid == listid2ref(proxo.myid).sysid) # if we already have this system's object, use that
          proxo = listid2ref(proxo.myid)
        else
          @list[proxo.myid] = proxo.id
          @obj_count = proxo.myid if (@obj_count < proxo.myid)
        end
        @sysid = proxo.sysid # to be sure to have the correct sysid in the container
        proxo
      end
      
      def listid2ref(lid)
        raise "Internal id #{lid} not found" unless x = @list[lid]
        ObjectSpace._id2ref(x)
      end
    end
#
# System
# This is a singleton class that keeps track of syscontainers
#
    class System
      include Singleton
      
      def System.start(directory_name, klass, *init_args)
        System.instance.start(directory_name, klass, *init_args)
      end
      
      def start(directory_name, klass, *init_args)
        @syscontainers ||= {}  # holds syscontainers by sysid
        scontainer = SysContainer.new
        @syscontainers[scontainer.sysid] = scontainer # store syscontainer, although sysid may be wrong at this point
        msys = scontainer.startMadeleine(directory_name, klass, *init_args)   # starts + gets the madeleine sys
        @syscontainers[msys.system.sysid] = scontainer  # store under permanent sysid - needed if there were no commands
        msys
      end
      
      def register_sysid(sid)  # sets the real sid for this thread's container - from a command
        @syscontainers[sid] = @syscontainers[Thread.current[:sysid]]
        Thread.current[:sysid] = sid
        @syscontainers[sid].sysid = sid 
        @syscontainers[sid].list.each {|o|  # set all the prox objects that already exist to have the right sysid
                         ObjectSpace._id2ref(o[1]).sysid = sid
                       }
      end
      
      def thread2sys # gets syscontainer of current system
        @syscontainers[Thread.current[:sysid]]
      end
    end
  end
end
