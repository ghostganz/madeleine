#
# Copyright(c) Anders Bengtsson 2003
#

require 'thread'

require 'clock'

module Madeleine

  class SnapshotPrevayler
    attr_reader :system

    def initialize(new_system, directory_name)
      @directory_name = directory_name
      ensure_directory_exists
      recover_system(new_system)
      @logger = Logger.new(directory_name)
      @lock = Mutex.new
    end

    def execute_command(command)
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
        snapshot_file = NumberedFile.new(@directory_name, "snapshot", id).to_s
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
  end

  #
  # Internal classes below
  #

  FILE_COUNTER_SIZE = 21

  class CommandLog
    class << self

      def log_file_names(directory_name)
        Dir.entries(directory_name).select {|name|
          name =~ /^\d{#{FILE_COUNTER_SIZE}}\.command\_log$/
        }
      end

      def file_name(id)
        name = ("0" * FILE_COUNTER_SIZE) + id.to_s
        name = name[name.length - FILE_COUNTER_SIZE, name.length - 1]
        name += ".command_log"
      end

    end
  end

  class Logger

    def initialize(directory_name)
      @directory_name = directory_name
      open_new_log
    end

    def reset
      delete_log_files
      open_new_log
    end

    def store(command)
      Marshal.dump(command, @log)
      @log.flush
      @log.fsync
    end

    def close
      @log.close
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

    def highest_log
      highest = 0
      log_file_names.each {|file_name|
        match = /^(\d{#{FILE_COUNTER_SIZE}})/.match(file_name)
        n = match[1].to_i
        if n > highest
          highest = n
        end
      }
      highest
    end

    def open_new_log
      name = NumberedFile.new(@directory_name, "command_log", highest_log + 1)
      @log = open(name.to_s, 'w')
    end
  end

  class Snapshot

    class << self

      def name(id)
        name = ("0" * FILE_COUNTER_SIZE) + id.to_s
        name = name[name.length - FILE_COUNTER_SIZE, name.length - 1]
        name += ".snapshot"
      end

      def highest_id(directory_name)
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
    end

    def initialize(directory_name, system)
      @directory_name, @system = directory_name, system
    end

    def take
      name = @directory_name + File::SEPARATOR + snapshot_name()
      open(name + '.tmp', 'w') {|snapshot|
        Marshal.dump(@system, snapshot)
      }
      File.rename(name + '.tmp', name)
    end

    private

    def snapshot_name
      Snapshot.name(Snapshot.highest_id(@directory_name) + 1)
    end
  end

  class NumberedFile

    def initialize(path, name, id)
      @path, @name, @id = path, name, id
    end

    def to_s
      result = @path
      result += File::SEPARATOR
      result += sprintf("%0#{FILE_COUNTER_SIZE}d", @id)
      result += '.'
      result += @name
    end
  end

end
