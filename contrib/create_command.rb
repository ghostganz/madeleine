#
# Dynamic creation of command classes.
#
# Contributed by James Britt 2004.
#

class Command
  Command::Target_map = {}

  def execute( system )
    cls = self.class.to_s
    cmd  = Command::Target_map[ cls ]
    system.send( cmd, *@_vars )
  end
end

# See http://www.rubytalk.com/cgi-bin/scat.rb/ruby/ruby-talk/56334
# But simplified/hacked so that it creates command/query classes
# This method defines a new class derived from Command.  The initialize
# method is defined such that all arguments are pushed onto an
# instance variable array named @_vars.  When 'execute' is called,
# this array will provide all the parameters to be sent to the
# method invoked on 'system'.
def createCommandClass( name, m_name )
  Object.const_set( name, Class.new( Command ) ).instance_eval do
    define_method( :initialize ) do  |*args|
      inst_vars = []
      args.each do |k|
        inst_vars.push( k )
      end
      instance_variable_set( "@_vars",  inst_vars )
    end
  end
  begin
    Command::Target_map[ name ] = m_name
  rescue Exception
    STDERR.puts( "Error setting value in  Command::Target_map:  #{$!}" )
  end
end
