
module Madeleine

  module Automatic
#
#
#
    class Automatic_upgrade_marshaller #:nodoc:
      def Automatic_upgrade_marshaller.load(io)
        restored_obj = Deserialize.load(io, Thread.current[:system].marshaller)
        ObjectSpace.each_object(Prox) {|o| Thread.current[:system].restore(o) if (o.sysid == restored_obj.sysid)}
        restored_obj
      end
      def Automatic_upgrade_marshaller.dump(obj, io = nil)
        Marshal.dump(obj)
        Thread.current[:system].marshaller.dump(Thread.current[:system].automatic_objects, io)
      end
    end

#
# 
#
    class Prox #:nodoc:
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
#
#
      def _dump(depth)
        if (!Thread.current[:snapshot_memory][0])
          Thread.current[:snapshot_memory][0] = true
          Thread.current[:system].automatic_objects.root_proxy = deproxify(self)
        end
        ""
      end

#
# Custom marshalling for Marshal - restore a Prox object.
#
      def Prox._load(str)
        raise ArgumentError, "Old format: Snapshot then upgrade", caller unless (AutomaticSnapshotMadeleine_upgrader === Thread.current[:system])
        x = Prox.new(nil)
        a = str.unpack("A8A30a*")
        x.myid = a[0].to_i
        x.sysid = a[1]
        x = Thread.current[:system].restore(x)
        x.thing = Marshal.load(a[2]) if (a[2] > "")
        x
      end
#
#
#
      def deproxify(o)
        Thread.current[:deprox_memory] ||= {}
        if (o.class == Prox)
          Automatic_proxy.new(deproxify(o.thing))
        else
          if (!Thread.current[:deprox_memory][o])
            Thread.current[:deprox_memory][o] = true
            o.instance_variables.each {|iv|
              ivsym = iv.intern
              ivval = o.instance_variable_get(ivsym)
              case ivval
              when Array
                arr = ivval.collect {|av| deproxify(av)}
                o.instance_variable_set(ivsym, arr)
              when Hash
                ha = Hash.new
                ivval.each {|k,v| ha[deproxify(k)] = deproxify(v)}
                o.instance_variable_set(ivsym, ha)
              when Range
                o.instance_variable_set(ivsym, Range.new(deproxify(ivval.begin), deproxify(ivval.end), ivval.exclude_end?))
              else
                o.instance_variable_set(ivsym, deproxify(ivval))
              end
            }
          end
          o
        end
      end
    end

#
# For upgrading automatic snapshot format
#
    class AutomaticSnapshotMadeleine_upgrader
      attr_accessor :marshaller
      attr_reader :list, :sysid, :automatic_objects

      def initialize(directory_name, marshaller=Marshal, persister=SnapshotMadeleine, &new_system_block)
        @sysid ||= Time.now.to_f.to_s + Thread.current.object_id.to_s # Gererate a new sysid
        @myid_count = 0
        @list = {}
        Thread.current[:system] = self # during system startup system should not create commands
        Thread.critical = true
        @@systems ||= {}  # holds systems by sysid
        @@systems[@sysid] = self
        Thread.critical = false
        @marshaller = marshaller # until attrb
        begin
          @persister = persister.new(directory_name, Automatic_upgrade_marshaller, &new_system_block)
          @list.delete_if {|k,v|  # set all the prox objects that now exist to have the right sysid
            begin
              ObjectSpace._id2ref(v).sysid = @sysid
              false
            rescue RangeError
              true # Id was to a GC'd object, delete it
            end
          }
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
        if (@list[proxo.myid])
          proxo = myid2ref(proxo.myid)
        else
          @list[proxo.myid] = proxo.object_id
          @myid_count = proxo.myid if (@myid_count < proxo.myid)
        end
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
          @automatic_objects = Automatic_objects.new
          @persister.take_snapshot
        ensure
          Thread.current[:snapshot_memory] = nil
          Thread.current[:system] = false
        end
      end
#
# Close method changes the sysid for Prox objects so they can't be mistaken for real ones in a new 
# system before GC gets them
#
      def close
        begin
          @list.each_key {|k| myid2ref(k).sysid = nil}
        rescue RangeError
          # do nothing
        end
        @persister.close
      end
    end

  end
end
