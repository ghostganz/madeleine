
unless $LOAD_PATH.include?("lib")
  $LOAD_PATH.unshift("lib")
end
unless $LOAD_PATH.include?("test")
  $LOAD_PATH.unshift("test")
end

require 'madeleine'
require 'test/unit'
require 'stringio'

class ExampleCommand
  attr :value

  def initialize(value)
    @value = value
  end

  def execute(system)
    system.add(@value)
  end
end

class CommandLogTest < Test::Unit::TestCase

  def setup
    @target = Madeleine::CommandLog.new(".", FileService.new)
  end

  def teardown
    @target.close
    File.delete(expected_file_name)
  end

  def test_logging
    f = open(expected_file_name, 'r')
    assert(f.stat.file?)
    @target.store(ExampleCommand.new(7))
    read_command = Marshal.load(f)
    assert_equal(ExampleCommand, read_command.class)
    assert_equal(7, read_command.value)
    assert_equal(f.stat.size, f.tell)
    @target.store(ExampleCommand.new(3))
    read_command = Marshal.load(f)
    assert_equal(3, read_command.value)
    assert_equal(f.stat.size, f.tell)
    f.close
  end

  def expected_file_name
    "000000000000000000001.command_log"
  end
end


class CommandLogTestUsingMocks < Test::Unit::TestCase

  def test_logging
    file_service = Object.new
    def file_service.exist?(path)
      [
        ["some", "path"].join(File::SEPARATOR),
        ["some", "path", "000000000000000000001.command_log"].join(File::SEPARATOR),
        ["some", "path", "000000000000000000002.command_log"].join(File::SEPARATOR),
        ["some", "path", "000000000000000000003.command_log"].join(File::SEPARATOR),
      ].include?(path)
    end
    def file_service.dir_entries(path, &block)
      if path != ["some", "path"].join(File::SEPARATOR)
        raise "wrong path"
      end
      [
        "000000000000000000001.command_log",
        "000000000000000000003.command_log",
        "000000000000000000002.command_log",
      ]
    end
    def file_service.open(path, flags)
      if path != ["some", "path", "000000000000000000004.command_log"].join(File::SEPARATOR)
        raise "wrong file id"
      end
      if flags != "wb"
        raise "wrong flags"
      end
      @file = StringIO.new
      @file
    end
    def file_service.file
      @file
    end

    target = Madeleine::CommandLog.new("some/path", file_service)

    command = ExampleCommand.new(1234)

    target.store(command)

    file_service.file.rewind
    assert_equal(Marshal.dump(command), file_service.file.read)

    # assert file was flushed
  end
end

