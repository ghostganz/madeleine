#
# Madeleine - Ruby Object Prevalence
#
# Author::    Anders Bengtsson <ndrsbngtssn@yahoo.se>
# Copyright:: Copyright (c) 2003-2012
#
# Usage:
#
#  require 'madeleine'
#
#  madeleine = SnapshotMadeleine.new("my_example_storage") {
#    SomeExampleApplication.new
#  }
#
#  madeleine.execute_command(command)
#

module Madeleine

  require 'thread'
  require 'sync'
  require 'fileutils'
  require 'madeleine/files'
  require 'madeleine/sanity'
  require 'madeleine/version'

  MADELEINE_VERSION = Madeleine::VERSION

  class SnapshotMadeleine

    # Builds a new Madeleine instance. If there is a snapshot available
    # then the system will be created from that, otherwise
    # <tt>new_system</tt> will be used. The state of the system will
    # then be restored from the command logs.
    #
    # You can provide your own snapshot marshaller, for instance using
    # YAML, instead of Ruby's built-in marshaller. The
    # <tt>snapshot_marshaller</tt> must respond to
    # <tt>load(stream)</tt> and <tt>dump(object, stream)</tt>. You
    # must use the same marshaller every time for a system.
    #
    # See: DefaultSnapshotMadeleine
    #
    # * <tt>directory_name</tt> - Storage directory to use. Will be created if needed.
    # * <tt>options</tt> - Options hash:
    #      * <tt>:snapshot_marshaller</tt> - Marshaller to use for system snapshots (defaults to Marshal)
    #      * <tt>:execution_context</tt> - Optional context to be passed to commands' execute() method as a second parameter
    # * <tt>new_system_block</tt> - Block to create a new system (if no stored system was found).
    def self.new(directory_name, options = {}, &new_system_block)
      if options.kind_of? Hash
        options = {
          :snapshot_marshaller => Marshal,
          :execution_context => nil
        }.merge(options)
      else
        # Backwards compat.
        options = {:snapshot_marshaller => options}
      end

      log_factory = DefaultLogFactory.new
      logger = Logger.new(directory_name,
                          log_factory)
      snapshotter = Snapshotter.new(directory_name,
                                    options[:snapshot_marshaller])
      recoverer = Recoverer.new(directory_name,
                                options[:snapshot_marshaller])
      system = recoverer.recover_snapshot(new_system_block)
      executer = Executer.new(system, options[:execution_context])
      recoverer.recover_logs(executer)
      DefaultSnapshotMadeleine.new(system, logger, snapshotter, executer)
    end
  end

  class DefaultSnapshotMadeleine

    # The prevalent system
    attr_reader :system

    def initialize(system, logger, snapshotter, executer)
      SanityCheck.instance.run_once

      @system = system
      @logger = logger
      @snapshotter = snapshotter
      @lock = Sync.new
      @executer = executer

      @closed = false
    end

    # Execute a command on the prevalent system.
    #
    # Commands must have a method <tt>execute(aSystem)</tt>.
    # Otherwise an error, <tt>Madeleine::InvalidCommandException</tt>,
    # will be raised.
    #
    # The return value from the command's <tt>execute()</tt> method is returned.
    #
    # * <tt>command</tt> - The command to execute on the system.
    def execute_command(command)
      verify_command_sane(command)
      @lock.synchronize do
        raise MadeleineClosedException if @closed
        @logger.store(command)
        @executer.execute(command)
      end
    end

    # Execute a query on the prevalent system.
    #
    # Only differs from <tt>execute_command</tt> in that the command/query isn't logged, and
    # therefore isn't allowed to modify the system. A shared lock is held, preventing others
    # from modifying the system while the query is running.
    #
    # * <tt>query</tt> - The query command to execute
    def execute_query(query)
      @lock.synchronize(:SH) do
        @executer.execute(query)
      end
    end

    # Take a snapshot of the current system.
    #
    # You need to regularly take a snapshot of a running system,
    # otherwise the logs will grow big and restarting the system will take a
    # long time. Your backups must also be done from the snapshot files,
    # since you can't make a consistent backup of a live log.
    #
    # A practical way of doing snapshots is a timer thread:
    #
    #  Thread.new(madeleine) {|madeleine|
    #    while true
    #      sleep(60 * 60 * 24) # 24 hours
    #      madeleine.take_snapshot
    #    end
    #  }
    def take_snapshot
      @lock.synchronize do
        @logger.close
        @snapshotter.take(@system)
        @logger.reset
      end
    end

    # Close the system.
    #
    # The log file is closed and no new commands can be received
    # by this Madeleine.
    def close
      @lock.synchronize do
        @logger.close
        @closed = true
      end
    end

    private

    def verify_command_sane(command)
      unless command.respond_to?(:execute)
        raise InvalidCommandException.new("Commands must have an 'execute' method")
      end
      if command.respond_to?(:marshal_dump)
        unless command.respond_to?(:marshal_load)
          raise InvalidCommandException.new("A Command with custom marshalling (mashal_dump()) must also define marshal_load()")
        end
      end
    end
  end

  class InvalidCommandException < Exception
  end

  class MadeleineClosedException < RuntimeError
  end

  #
  # Internal classes below
  #

  FILE_COUNTER_SIZE = 21 #:nodoc:

  class Executer #:nodoc:
    def initialize(system, context = nil)
      @system = system
      @context = context
      @in_recovery = false
    end

    def execute(command)
      begin
        if @context
          command.execute(@system, @context)
        else
          command.execute(@system)
        end
      rescue
        raise unless @in_recovery
      end
    end

    def recovery
      begin
        @in_recovery = true
        yield
      ensure
        @in_recovery = false
      end
    end
  end

  class Recoverer #:nodoc:

    def initialize(directory_name, marshaller)
      @directory_name, @marshaller = directory_name, marshaller
    end

    def recover_snapshot(new_system_block)
      system = nil
      id = SnapshotFile.highest_id(@directory_name)
      if id > 0
        snapshot_file = SnapshotFile.new(@directory_name, id).name
        open(snapshot_file, "rb") do |snapshot|
          system = @marshaller.load(snapshot)
        end
      else
        system = new_system_block.call
      end
      system
    end

    def recover_logs(executer)
      executer.recovery do
        CommandLog.log_file_names(@directory_name, FileService.new).each do |file_name|
          open("#{@directory_name}#{File::SEPARATOR}#{file_name}", "rb") do |log|
            recover_log(executer, log)
          end
        end
      end
    end

    private

    def recover_log(executer, log)
      until log.eof?
        command = Marshal.load(log)
        executer.execute(command)
      end
    end
  end

  class NumberedFile #:nodoc:

    def initialize(path, name, id)
      @path, @name, @id = path, name, id
    end

    def name
      [
        @path,
        File::SEPARATOR,
        sprintf("%0#{FILE_COUNTER_SIZE}d", @id),
        '.',
        @name
      ].join
    end
  end

  class CommandLog #:nodoc:

    def self.log_file_names(directory_name, file_service)
      return [] unless file_service.exist?(directory_name)
      result = file_service.dir_entries(directory_name).select {|name|
        name =~ /^\d{#{FILE_COUNTER_SIZE}}\.command_log$/
      }
      result.each do |name|
        name.untaint
      end
      result.sort
    end

    def initialize(path, file_service)
      id = self.class.highest_log(path, file_service) + 1
      numbered_file = NumberedFile.new(path, "command_log", id)
      @file = file_service.open(numbered_file.name, 'wb')
    end

    def close
      @file.close
    end

    def store(command)
      # Dumping to intermediate String instead of to IO directly, to make sure
      # all of the marshalling worked before we write anything to the log.
      data = Marshal.dump(command)
      @file.write(data)
      @file.flush
      @file.fsync
    end

    def self.highest_log(directory_name, file_service)
      highest = 0
      log_file_names(directory_name, file_service).each do |file_name|
        match = /^(\d{#{FILE_COUNTER_SIZE}})/.match(file_name)
        n = match[1].to_i
        if n > highest
          highest = n
        end
      end
      highest
    end
  end

  class DefaultLogFactory #:nodoc:
    def create_log(directory_name)
      CommandLog.new(directory_name, FileService.new)
    end
  end

  class Logger #:nodoc:

    def initialize(directory_name, log_factory)
      @directory_name = directory_name
      @log_factory = log_factory
      @log = nil
      @pending_tick = nil
      ensure_directory_exists
    end

    def ensure_directory_exists
      unless File.exist?(@directory_name)
        FileUtils.mkpath(@directory_name)
      end
    end

    def reset
      close
      delete_log_files
    end

    def store(command)
      if command.kind_of?(Madeleine::Clock::Tick)
        @pending_tick = command
      else
        if @pending_tick
          internal_store(@pending_tick)
          @pending_tick = nil
        end
        internal_store(command)
      end
    end

    def internal_store(command)
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

    def delete_log_files
      names = Dir.glob("#{@directory_name}#{File::SEPARATOR}*.command_log")
      names.each do |name|
        name.untaint
        File.delete(name)
      end
    end

    def open_new_log
      @log = @log_factory.create_log(@directory_name)
    end
  end

  class SnapshotFile < NumberedFile #:nodoc:

    def self.highest_id(directory_name)
      return 0 unless File.exist?(directory_name)
      suffix = "snapshot"
      highest = 0
      Dir.foreach(directory_name) do |file_name|
        match = /^(\d{#{FILE_COUNTER_SIZE}}\.#{suffix}$)/.match(file_name)
        next unless match
        n = match[1].to_i
        if n > highest
          highest = n
        end
      end
      highest
    end

    def self.next(directory_name)
      new(directory_name, highest_id(directory_name) + 1)
    end

    def initialize(directory_name, id)
      super(directory_name, "snapshot", id)
    end
  end

  class Snapshotter #:nodoc:

    def initialize(directory_name, marshaller)
      @directory_name, @marshaller = directory_name, marshaller
    end

    def take(system)
      numbered_file = SnapshotFile.next(@directory_name)
      name = numbered_file.name
      open("#{name}.tmp", 'wb') do |snapshot|
        @marshaller.dump(system, snapshot)
        snapshot.flush
        snapshot.fsync
      end
      File.rename("#{name}.tmp", name)
    end
  end

  module Clock #:nodoc:
    class Tick #:nodoc:

      def initialize(time)
        @time = time
      end

      def execute(system)
        system.clock.forward_to(@time)
      end
    end
  end
end

SnapshotMadeleine = Madeleine::SnapshotMadeleine
