require 'madeleine'
require 'madeleine/automatic'

class Service_settings
  attr_accessor :storage_path, :snapshot_interval, :automatic_snapshots
  def initialize(path = "storage", interval = 60*60*24, snapshots = true)
    @storage_path = path
    @snapshot_interval = interval
    @automatic_snapshots = snapshots
  end
end
  
class Madeleine_service
  include Madeleine::Automatic::Interceptor

  @@settings = nil
  @@server = nil

  class << self
    def settings(settings = nil)
      @@settings = settings if settings
      @@settings = Service_settings.new unless @@settings
      @@settings
    end
  
    def clean_storage(settings = nil)
      Madeleine_server.clean_storage(Madeleine_service.settings(settings))
    end
  
    def instance(settings = nil)
      @@server = Madeleine_server.new(self, Madeleine_service.settings(settings)) unless @@server
      @@server.system
    end
  
    def restart
      Madeleine_service.clean_storage
      @@server = Madeleine_server.new(self, @@settings)
      @@server.system
    end

    def stop
      @@server.close
      @@server = nil
    end
  end
end

class Madeleine_server
  # Clears all the command_log and snapshot files located in the storage directory, so the
  # database is essentially dropped and recreated as blank
  def Madeleine_server.clean_storage(settings = Service_settings.new)
    begin 
      Dir.foreach(settings.storage_path) do |file|
        File.delete(settings.storage_path + File::SEPARATOR + file) if file =~ /(command_log|snapshot)$/
      end
    rescue
      Dir.mkdir(settings.storage_path)
    end
  end

  def initialize(service, settings = Service_settings.new)
    @settings = settings
    @asm_server = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(@settings.storage_path) { service.new }
    if @settings.automatic_snapshots
      start_snapshot_thread
    else
      @ss_thread = nil
    end
  end

  def system
    @asm_server.system
  end

  def close
    @ss_thread.exit if @ss_thread
    @asm_server.close
  end
  
  def start_snapshot_thread
    @ss_thread = Thread.new {
      while true
        sleep(@settings.snapshot_interval)
        @asm_server.take_snapshot
      end
    }
  end
end
