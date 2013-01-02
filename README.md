# Madeleine

Madeleine is a Ruby implementation of transparent persistence of business
objects, using command logging and complete system snapshots.

https://github.com/ghostganz/madeleine

### Usage

```ruby
require 'madeleine'

# Create an application as a prevalent system

madeleine = SnapshotMadeleine.new("my_example_storage") {
  # Creating the initial empty system. This is how the application
  # is bootstrapped on each startup (until the first snapshot is taken).
  # All the persistent data needs to be reachable from this object.
  # For this example, the application's whole dataset is a hash
  # with a counter:
  {:counter => 0}
}

# To operate on the system, we need commands. For this example,
# we can do additions to our counter:
class AdditionCommand
  def initialize(number)
    @number = number
  end

  def execute(system)
    # This is the only place from where we're allowed to modify
    # the system.
    system[:counter] += @number
  end
end

# Do modifications of the system by sending commands through
# the Madeleine instance:

command = AdditionCommand.new(12)
madeleine.execute_command(command)

# The commands are written to the command log before executed.
# The next time the application starts, all the commands in the
# log are re-applied to the system, returning it to the state it
# had when it was shut down.

# To avoid long start-up times when the command log gets large,
# you can do occasional snapshots of the entire system. You must
# also do a snapshot before deploying any changes in your application
# logic.

madeleine.take_snapshot
```

### Requirements

* Ruby 1.8.7 or later

### Contact

Homepage: https://github.com/ghostganz/madeleine

### License

BSD (see the file ```COPYING```)

### Credits

Anders Bengtsson   -   Prevalence core impl.
Stephen Sykes      -   Automatic commands impl.

Madeleine's design is based on Prevayler, the original Java
prevalence layer.

With the help of patches, testing and feedback from:

Steve Conover, David Heinemeier Hansson, Johan Lind, Håkan Råberg,
IIMA Susumu, Martin Tampe and Jon Tirsén

Thanks to Klaus Wuestefeld and the Prevayler developers for the
model of this software; to Minero Aoki for the installer; to Matz and
the core developers for the Ruby language!
