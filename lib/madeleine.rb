#
# Madeleine - Ruby Object Prevalence
#
# Copyright(c) Anders Bengtsson 2003
#

require 'thread'
require 'sync'
#require '../rwlock'

module Madeleine

  MADELEINE_VERSION = "0.3"

  class SnapshotMadeleine
    attr_reader :system

    def initialize(directory_name, marshaller=Marshal, &new_system_block)
      @directory_name = directory_name
      @marshaller = marshaller
      @in_recovery = false
      @closed = false
      @lock = create_lock
      ensure_directory_exists
      recover_system(new_system_block)
      @logger = create_logger(directory_name, log_factory)
    end

    def execute_command(command)
      verify_command_sane(command)
      @lock.synchronize {
        raise "closed" if @closed
        @logger.store(command)
        execute_without_storing(command)
      }
    end

    def take_snapshot
      @lock.synchronize {
        @logger.close
        Snapshot.new(@directory_name, system, @marshaller).take
        @logger.reset
      }
    end

    def close
      @lock.synchronize {
        @logger.close
        @closed = true
      }
    end

    private

    def create_lock
      Mutex.new
    end

    def create_logger(directory_name, log_factory)
      Logger.new(directory_name, log_factory)
    end

    def log_factory
      DefaultLogFactory.new
    end

    def execute_without_storing(command)
      begin
        command.execute(system)
      rescue
        raise unless @in_recovery
      end
    end

    def recover_system(new_system_block)
      @in_recovery = true
      id = SnapshotFile.highest_id(@directory_name)
      if id > 0
        snapshot_file = SnapshotFile.new(@directory_name, id).name
        open(snapshot_file) {|snapshot|
          @system = @marshaller.load(snapshot)
        }
      else
        @system = new_system_block.call
      end

      CommandLog.log_file_names(@directory_name).each {|file_name|
        open(@directory_name + File::SEPARATOR + file_name) {|log|
          recover_log(log)
        }
      }
      @in_recovery = false
    end

    def recover_log(log)
      while ! log.eof?
        command = Marshal.load(log)
        execute_without_storing(command)
      end
    end

    def ensure_directory_exists
      if ! File.exist?(@directory_name)
        Dir.mkdir(@directory_name)
      end
    end

    def verify_command_sane(command)
      if ! command.respond_to?(:execute)
        raise InvalidCommandException.new("Commands must have an 'execute' method")
      end
    end
  end

  class InvalidCommandException < Exception
  end

  #
  # Internal classes below
  #

  FILE_COUNTER_SIZE = 21

  class NumberedFile

    def initialize(path, name, id)
      @path, @name, @id = path, name, id
    end

    def name
      result = @path
      result += File::SEPARATOR
      result += sprintf("%0#{FILE_COUNTER_SIZE}d", @id)
      result += '.'
      result += @name
    end
  end

  class CommandLog < NumberedFile

    def self.log_file_names(directory_name)
      result = Dir.entries(directory_name).select {|name|
        name =~ /^\d{#{FILE_COUNTER_SIZE}}\.command\_log$/
      }
      result.each {|name| name.untaint }
      result
    end

    def initialize(path)
      id = CommandLog.highest_log(path) + 1
      super(path, "command_log", id)
      @file = open(name, 'w')
    end

    def close
      @file.close
    end

    def store(command)
      Marshal.dump(command, @file)
      @file.flush
      @file.fsync
    end

    def self.highest_log(directory_name)
      highest = 0
      log_file_names(directory_name).each {|file_name|
        match = /^(\d{#{FILE_COUNTER_SIZE}})/.match(file_name)
        n = match[1].to_i
        if n > highest
          highest = n
        end
      }
      highest
    end
  end

  class DefaultLogFactory
    def create_log(directory_name)
      CommandLog.new(directory_name)
    end
  end

  class Logger

    def initialize(directory_name, log_factory)
      @directory_name = directory_name
      @log_factory = log_factory
      @log = nil
    end

    def reset
      close
      delete_log_files
    end

    def store(command)
      if @log.nil?
        open_new_log
      end
      @log.store(command)
    end

    def close
      return if @log.nil?
      @log.close
      @log = nil
    end

    private

    def log_file_names
      CommandLog.log_file_names(@directory_name)
    end

    def delete_log_files
      log_file_names.each {|name|
        File.delete(@directory_name + File::SEPARATOR + name)
      }
    end

    def open_new_log
      @log = @log_factory.create_log(@directory_name)
    end
  end

  class SnapshotFile < NumberedFile

    def self.highest_id(directory_name)
      highest = 0
      Dir.foreach(directory_name) {|file_name|
        match = /^(\d{#{FILE_COUNTER_SIZE}}\.snapshot$)/.match(file_name)
        next unless match
        n = match[1].to_i
        if n > highest
          highest = n
        end
      }
      highest
    end

    def self.next(directory_name)
      new(directory_name, highest_id(directory_name) + 1)
    end

    def initialize(directory_name, id)
      super(directory_name, "snapshot", id)
    end
  end

  class Snapshot

    def initialize(directory_name, system, marshaller)
      @directory_name, @system, @marshaller = directory_name, system, marshaller
    end

    def take
      numbered_file = SnapshotFile.next(@directory_name)
      name = numbered_file.name
      open(name + '.tmp', 'w') {|snapshot|
        @marshaller.dump(@system, snapshot)
        snapshot.flush
        snapshot.fsync
      }
      File.rename(name + '.tmp', name)
    end
  end
end

SnapshotMadeleine = Madeleine::SnapshotMadeleine

