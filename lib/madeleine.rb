#
# Madeleine - Ruby Object Prevalence
#
# Copyright(c) Anders Bengtsson 2003
#

require 'thread'

module Madeleine

  MADELEINE_VERSION = "0.0"

  class SnapshotPrevayler
    attr_reader :system

    def initialize(new_system, directory_name, log_factory=DefaultLogFactory.new)
      @directory_name = directory_name
      ensure_directory_exists
      recover_system(new_system)
      @logger = Logger.new(directory_name, log_factory)
      @lock = Mutex.new
    end

    def execute_command(command)
      verify_command_sane(command)
      @lock.synchronize {
        @logger.store(command)
        execute_without_storing(command)
      }
    end

    def take_snapshot
      @lock.synchronize {
        @logger.close
        Snapshot.new(@directory_name, system).take
        @logger.reset
      }
    end

    private

    def execute_without_storing(command)
      command.execute(system)
    end

    def recover_system(new_system)
      id = Snapshot.highest_id(@directory_name)
      if id > 0
        snapshot_file = NumberedFile.new(@directory_name, "snapshot", id).name
        open(snapshot_file) {|snapshot|
          @system = Marshal.load(snapshot)
        }
      else
        @system = new_system
      end

      CommandLog.log_file_names(@directory_name).each {|file_name|
        open(@directory_name + File::SEPARATOR + file_name) {|log|
          recover_log(log)
        }
      }
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
      Dir.entries(directory_name).select {|name|
        name =~ /^\d{#{FILE_COUNTER_SIZE}}\.command\_log$/
      }
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
      unless @log.nil?
        @log.close
        @log = nil
      end
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

    def initialize(directory_name, id)
      super(directory_name, "snapshot", id)
    end
  end

  class Snapshot

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

    def initialize(directory_name, system)
      @directory_name, @system = directory_name, system
    end

    def take
      numbered_file = SnapshotFile.new(@directory_name,
                                       Snapshot.highest_id(@directory_name) + 1)
      name = numbered_file.name
      open(name + '.tmp', 'w') {|snapshot|
        Marshal.dump(@system, snapshot)
        snapshot.flush
        snapshot.fsync
      }
      File.rename(name + '.tmp', name)
    end
  end

end

require 'madeleine/clock'
