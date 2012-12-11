
unless $LOAD_PATH.include?("lib")
  $LOAD_PATH.unshift("lib")
end
unless $LOAD_PATH.include?("test")
  $LOAD_PATH.unshift("test")
end

require 'madeleine'
require 'stringio'

class CommandLogTest < MiniTest::Unit::TestCase

  class ExampleCommand
    attr :value

    def initialize(value)
      @value = value
    end

    def execute(system)
      system.add(@value)
    end
  end

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
    file = MiniTest::Mock.new
    file.expect(:write, true, [Marshal.dump(command)])
    file.expect(:flush, true)
    file.expect(:fsync, true)

    file_service = MiniTest::Mock.new
    file_service.expect(:exist?, true, ["some/path"])
    file_service.expect(:dir_entries, [], ["some/path"])
    file_service.expect(:open, file, ["some/path/000000000000000000001.command_log", "wb"])

    target = Madeleine::CommandLog.new("some/path", file_service)
    target.store(command)

    file.verify
    file_service.verify
  end

  class ExplodingObjectError < RuntimeError
  end

  class ExplodingObject
    def marshal_dump
      raise ExplodingObjectError.new
    end

    def marshal_load(obj)
    end
  end

  class ExplodingCommand
    def execute(system)
    end

    def marshal_dump
      large_string = 'x' * 5000 # Large enough to force write buffer flush
      [large_string, ExplodingObject.new]
    end

    def marshal_load(obj)
    end
  end

  class FileNotToBeWritten
    def initialize
      @anything_written = false
    end

    def write(arg)
      @anything_written = true
    end

    def verify
      raise "Stuff was written" if @anything_written
    end
  end

  def test_failure_during_marshalling_writes_nothing_to_log
    command = ExplodingCommand.new
    file = FileNotToBeWritten.new

    file_service = MiniTest::Mock.new
    file_service.expect(:exist?, true, ["some/path"])
    file_service.expect(:dir_entries, [], ["some/path"])
    file_service.expect(:open, file, ["some/path/000000000000000000001.command_log", "wb"])

    target = Madeleine::CommandLog.new("some/path", file_service)
    assert_raises(ExplodingObjectError) do
      target.store(command)
    end

    file.verify
  end
end
