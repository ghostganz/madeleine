#
# Author::    Stephen Sykes <sds@stephensykes.com>, David Heinemeier Hansson <david@loudthinking.com>
# Copyright:: Copyright (c) 2004
#
# This is originally derived from Instiki code by David Heinemeier Hansson.
#
# The idea here is to make it easier to use Madeleine by taking care of creating an automatic snapshot
# thread - something you may typically want have running so it can snapshot once per day in the background.
# Also some other features are provided such as a convenient way to clean your storage directory, and
# a single method to stop Madeleine, clean the storage, and restart it (clean_instance).
#
require 'madeleine'
require 'madeleine/automatic'

module Madeleine  
  #
  # This contains settings for your madeleine service
  # The defaults are sane (store files in directory "storage", snapshot once per day, persist using
  # AutomaticSnapshotMadeleine), so you may not need to interact with this class.
  #
  # You can disable automatic snapshots by setting the snapshot interval to 0.
  #
  class Service_settings
    attr_accessor :storage_path, :snapshot_interval, :automatic_snapshots, :persister
    def initialize(path = "storage", interval = 60*60*24, persister = AutomaticSnapshotMadeleine)
      @storage_path = path
      @snapshot_interval = interval
      @persister = persister
    end
  end
  #
  # Use this class as the base class for the object you want to persist.
  # This class can only be used once - there should only be one madeleine system in use.
  #
  class Madeleine_service
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
      
      def clean_instance
        Madeleine_service.stop if @@server
        Madeleine_service.clean_storage
        @@server = Madeleine_server.new(self, @@settings)
        @@server.system
      end

      def stop
        @@server.close
        @@server = nil
      end
    end

    def take_snapshot
      @@server.take_snapshot
    end
  end

  #
  # Use this class as the base class for the object you want to persist if you want automatic commands.
  #
  class Automatic_service < Madeleine_service
    include Madeleine::Automatic::Interceptor
    automatic_read_only :take_snapshot
  end
  # 
  # This class takes care of starting Madeleine, and of the snapshot thread
  #
  class Madeleine_server
    #
    # Clears all the command_log and snapshot files located in the storage directory, so the
    # database is essentially dropped and recreated as blank
    #
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
      @sm_server = @settings.persister.new(@settings.storage_path) { service.new }
      if @settings.snapshot_interval != 0
        start_snapshot_thread
      else
        @ss_thread = nil
      end
    end

    def system
      @sm_server.system
    end

    def close
      @ss_thread.exit if @ss_thread
      @sm_server.close
    end
    
    def start_snapshot_thread
      @ss_thread = Thread.new {
        while true
          sleep(@settings.snapshot_interval)
          take_snapshot
        end
      }
    end

    def take_snapshot
      @sm_server.take_snapshot
    end
  end

end
