#
# A dictionary server using Distributed Ruby (DRb).
#
# All modifications to the dictionary are done as commands,
# while read-only queries like 'lookup' can be done directly.
#
# First launch this server in the background, then use
# dictionary_client.rb to look up and add items to the
# dictionary.
# You can kill the server at any time. The contents of the
# dictionary will still be there when you restart it.
#
# DRb is available at http://raa.ruby-lang.org/list.rhtml?name=druby
#

$LOAD_PATH.unshift(".." + File::SEPARATOR + "lib")
require 'madeleine'

require 'drb'


class Dictionary

  def initialize
    @data = {}
  end

  def add(key, value)
    @data[key] = value
  end

  def lookup(key)
    @data[key]
  end
end


class Addition

  def initialize(key, value)
    @key, @value = key, value
  end

  def execute(system)
    system.add(@key, @value)
  end
end


class DictionaryServer

  def initialize(madeleine)
    @madeleine = madeleine
    @dictionary = madeleine.system
  end

  def add(key, value)
    @madeleine.execute_command(Addition.new(key, value))
  end

  def lookup(key)
    @dictionary.lookup(key)
  end
end


system = Dictionary.new
madeleine = Madeleine::SnapshotPrevayler.new(system, "dictionary-base")

Thread.new(madeleine) {
  puts "Taking snapshot every 30 seconds."
  while true
    sleep(30)
    madeleine.take_snapshot
  end
}

DRb.start_service("druby://localhost:1234", DictionaryServer.new(madeleine))
DRb.thread.join

