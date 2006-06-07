
unless $LOAD_PATH.include?("lib")
  $LOAD_PATH.unshift("lib")
end
unless $LOAD_PATH.include?("test")
  $LOAD_PATH.unshift("test")
end

require 'madeleine'
require 'test/unit'
require 'stringio'
require 'sillymock'

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

  def test_file_opening
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
      @was_open_called = true
      if path != ["some", "path", "000000000000000000004.command_log"].join(File::SEPARATOR)
        raise "wrong file id"
      end
      if flags != "wb"
        raise "wrong flags"
      end
      StringIO.new
    end
    def file_service.was_open_called
      @was_open_called
    end

    target = Madeleine::CommandLog.new("some/path", file_service)
    assert(file_service.was_open_called)
  end

  def test_writing_command
    command = ExampleCommand.new(1234)
    file = Mock.new
    file.expects(:write, [Marshal.dump(command)])
    file.expects(:flush)
    file.expects(:fsync)

    file_service = Mock.new
    file_service.expects(:exist?, ["some/path"]).return_value(true)
    file_service.expects(:dir_entries, ["some/path"]).return_value([])
    file_service.expects(:open).return_value(file)

    target = Madeleine::CommandLog.new("some/path", file_service)
    target.store(command)

    file.verify
    file_service.verify
  end
end
