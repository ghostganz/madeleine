#!/usr/local/bin/ruby -w
#
# Copyright(c) 2003 Stephen Sykes
#
# Some components taken from test_persistence.rb
# Copyright(c) 2003 Anders Bengtsson
#

$LOAD_PATH.unshift("lib")

require 'madeleine'
require 'madeleine/automatic'
require 'test/unit'

class A
  include Madeleine::Automatic::Interceptor
  attr_accessor :z,:k
  def initialize
    @k=1
  end
end

class B
  include Madeleine::Automatic::Interceptor
  attr_accessor :y, :s
  def initialize(a)
    @y = C.new(a)
  end
end

class C
  include Madeleine::Automatic::Interceptor
  attr_accessor :x, :a
  def initialize(x)
    @x = x
    @a ||= D.new
  end
end

# direct changes in this class are not saved, except at snapshot
class D
  attr_accessor :w
end

class F
  include Madeleine::Automatic::Interceptor
  attr_accessor :z
  def plus1
    @z += 1
  end
end

class G
  include Madeleine::Automatic::Interceptor
  attr_accessor :y,:a
  def initialize
    @y = H.new
  end
end

class H
  include Madeleine::Automatic::Interceptor
  attr_accessor :w
  def minus1
    @w -= 1
  end
end

class I
  include Madeleine::Automatic::Interceptor
  def initialize
    @x = J.new
  end
  def testyield
    r = false
    @x.yielder {|c| r = true if c == 1}
    r
  end
end

class J
  include Madeleine::Automatic::Interceptor
  def yielder
    yield 1
  end
end

class AutoTest < Test::Unit::TestCase

  def delete_directory(directory_name)
    return unless File.exist?(directory_name)
    Dir.foreach(directory_name) do |file|
      next if file == "."
      next if file == ".."
      assert(File.delete(directory_name + File::SEPARATOR + file) == 1,
             "Unable to delete #{file}")
    end
    Dir.delete(directory_name)
  end

  def create_new_system(klass, dir, *arg)
    delete_directory(dir)
    Thread.critical = true
    @system_bases << dir
    Thread.critical = false
    Madeleine::Automatic::AutomaticSnapshotMadeleine.new(dir) { klass.new(*arg) }
  end

  def prevalence_base
    "AutoPrevalenceTestBase" + self.class.to_s
  end

  def setup
    @system_bases = []
  end

  def teardown
    @system_bases.each {|dir| 
      delete_directory(dir)
    }
  end

end

# Basic test, and that system works in SAFE level 1
class BasicTest < AutoTest
  def test_main
    mad_a = create_new_system(A, prevalence_base)
    mad_a.close
    mad_a0 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { A.new }
    assert_equal(1, mad_a0.system.k, "No commands or snapshot")
    mad_a0.system.z = 0
    mad_a0.system.z += 1
    assert_equal(1, mad_a0.system.z, "Object changes")
    mad_a0.system.z -= 10
    assert_equal(-9, mad_a0.system.z, "Object changes")
    mad_a0.close
    mad_a2 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { A.new }
    assert_equal(-9, mad_a2.system.z, "Commands but no snapshot")
    mad_a2.take_snapshot
    mad_a3 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { A.new }
    assert_equal(-9, mad_a3.system.z, "Snapshot but no commands")
    mad_a3.system.z -= 6
    mad_a3.system.z -= 3
    mad_a4 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { A.new }
    assert_equal(-18, mad_a4.system.z, "Snapshot and commands")
  end

  def test_main_in_safe_level_one
    thread = Thread.new {
      $SAFE = 1
      test_main
    }
    thread.join
  end
end

class ObjectOutsideTest < AutoTest
  def test_main
    mad = create_new_system(A, prevalence_base)
    assert_raises(RuntimeError) {
                 mad.system.z = A.new  # app object created outside system
               }
  end
end

# Passing a block when it would generate a command is not allowed because blocks cannot
# be serialised.  However, block passing/yielding inside the application is ok.
class BlockGivenTest < AutoTest
  def test_main
    mad = create_new_system(J, prevalence_base)
    assert_raises(RuntimeError) {
                   mad.system.yielder {|a| a}
                 }
    mad2 = create_new_system(I, prevalence_base+"2")
    assert(mad2.system.testyield, "Internal block passing")
  end
end

class NonPersistedObjectTest < AutoTest
  def test_main
    mad_b = create_new_system(B, prevalence_base, 0)
    mad_b.system.y.x -= 1
    assert_equal(-1, mad_b.system.y.x, "Direct change of object inside main object")

    mad_b.system.y.a.w ||= "hello"  # not saved
    mad_b.system.y.a.w += " again"  # not saved

    assert_equal("hello again", mad_b.system.y.a.w, "Non persisted object before close")

    mad_b.close
    mad_b2 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { B.new(0) }
    assert_equal(nil, mad_b2.system.y.a.w, "Non persisted object after restart, no snapshot")
    mad_b2.system.y.a.w ||= "hello"  # not saved
    mad_b2.system.y.a.w += " again"  # not saved
    mad_b2.take_snapshot             # NOW saved
    mad_b2.system.y.a.w += " again"  # not saved
    assert_equal("hello again again", mad_b2.system.y.a.w, "Non persisted object after take_snapshot and 1 change")

    mad_b2.close
    mad_b3 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { B.new(0) }
    assert_equal("hello again", mad_b3.system.y.a.w, "Non persisted object after restore (back to snapshotted state)")
  end
end

class RefInExternalObjTest < AutoTest
  def test_main
    mad_c = create_new_system(B, prevalence_base, 0)
    x = D.new
    x.w = mad_c.system.y
    mad_c.system.s = x  # pass in an external object that contains a ref to obj in ths system

    mad_c.system.s.w.x += 1      # Increment counter via external obj
    assert_equal(1, mad_c.system.y.x, "Change via external object")
    mad_c.system.y.x += 1        # Increment counter directly
    assert_equal(2, mad_c.system.s.w.x, "Direct change")
    mad_c.close

    mad_c2 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { B.new(0) }
    assert_equal(2, mad_c2.system.s.w.x, "Value via external object after commands/restore")
    assert_equal(2, mad_c2.system.y.x, "Direct value after restore")
    mad_c2.take_snapshot
    mad_c2.close

    mad_c3 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { B.new(0) }
    assert_equal(2, mad_c3.system.s.w.x, "Value via external object after snapshot/restore")
    assert_equal(2, mad_c3.system.y.x, "Direct value after snapshot/restore")

    mad_c3.system.s.w.x += 1      # Increment counter via external obj
    mad_c3.system.y.x += 1        # Increment counter directly
    mad_c3.close

    mad_c4 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { B.new(0) }
    assert_equal(4, mad_c4.system.s.w.x, "Value via external object after snapshot+commands/restore")
    assert_equal(4, mad_c4.system.y.x, "Direct value after snapshot+commands/restore")
  end
end

class BasicThreadSafetyTest < AutoTest
  def test_main
    mad_d = create_new_system(F, prevalence_base)
    mad_d.system.z = 0
    mad_e = create_new_system(G, prevalence_base+"2")
    mad_e.system.y.w = 0
    
    x = []
    25.times {|n|
      x[n] = Thread.new {
               5.times {
                 sleep(rand/10)
                 mad_d.system.plus1
                 mad_e.system.y.minus1
               }
           }
    }
    25.times {|n|
      x[n].join
    }
    assert_equal(125, mad_d.system.z, "mad_d.z")
    assert_equal(-125, mad_e.system.y.w, "mad_e.y.w")

    mad_e.close
    mad_e2 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base+"2") { G.new }

    25.times {|n|
      x[n] = Thread.new {
               5.times {
                 sleep(rand/10)
                 mad_d.system.plus1
                 mad_e2.system.y.minus1
               }
           }
    }
    sleep(0.1)
    mad_d.take_snapshot
    mad_e2.take_snapshot
    25.times {|n|
      x[n].join
    }
    assert_equal(250, mad_d.system.z, "mad_d.z")
    assert_equal(-250, mad_e2.system.y.w, "mad_e2.y.w")
  
  end
end

class InvalidMethodTest < AutoTest
  def test_main
    mad_f = create_new_system(A, prevalence_base)
    mad_f.system.z = -1
    assert_raises(NoMethodError) {
                   mad_f.system.not_a_method
                 }
    assert_equal(-1, mad_f.system.z, "System functions after NoMethodError")
  end
end

class CircularReferenceTest < AutoTest
  def test_main
    mad_g = create_new_system(G, prevalence_base)
    mad_g.system.y.w = mad_g.system
    mad_g.close
    mad_g2 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { G.new }
    assert(mad_g2.system == mad_g2.system.y.w.y.w.y.w, "Circular reference after command/restore")
    mad_g2.take_snapshot
    mad_g2.close
    mad_g3 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { G.new }
    assert(mad_g3.system == mad_g3.system.y.w.y.w.y.w, "Circular reference after snapshot/restore")
    mad_g3.system.y.w.y.w.y.w.a = 1
    assert_equal(1, mad_g3.system.a, "Circular reference change")
    mad_g3.close
    mad_g4 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base) { G.new }
    assert_equal(1, mad_g4.system.y.w.y.w.y.w.a, "Circular reference after snapshot+commands/restore")
  end
end

class AutomaticCustomMarshalllerTest < AutoTest
  def load(from)
    if (from.kind_of?(IO))
      s = from.read
      a = s.unpack("A4a*")
      Madeleine::Automatic::Prox._load(a[1])
    else
      x = A.new
      x.z = from
      x.thing
    end
  end

  def dump(item, io=nil)
    if (item.kind_of?(Madeleine::Automatic::Prox))
      io.write("Prox")
      io.write(item._dump(-1))
    else
      item.z
    end
  end

  def test_main
    dir = prevalence_base
    delete_directory(dir)
    @system_bases << dir
    mad_h = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(dir, self) { A.new }
    mad_h.system.z = "abc"
    mad_h.take_snapshot
    mad_h.system.z += "d"
    mad_h.close
    mad_h2 = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(dir, self) { A.new }
    assert_equal("abcd", mad_h2.system.z, "Custom marshalling after snapshot+commands/restore")
  end
end

# tests thread safety during system creation
class ThreadedStartupTest < AutoTest
  def test_main
    x,mad = [],[]
    20.times {|n|
      x[n] = Thread.new {
               sleep(rand/10)
               mad[n] = create_new_system(F, prevalence_base+n.to_s)
               mad[n].system.z = 0
               n.times {
                 mad[n].system.plus1
               }
               assert_equal(n, mad[n].system.z, "mad[#{n}].z")
               mad[n].take_snapshot if (n%2 == 0)
             }
    }
    20.times {|n|
      x[n].join
      mad_i = Madeleine::Automatic::AutomaticSnapshotMadeleine.new(prevalence_base+n.to_s) { F.new }
      assert_equal(n, mad_i.system.z, "mad[#{n}].z")
    }
  end
end


def add_automatic_tests(suite)
  suite << BasicTest.suite
  suite << ObjectOutsideTest.suite
  suite << BlockGivenTest.suite
  suite << NonPersistedObjectTest.suite
  suite << RefInExternalObjTest.suite
  suite << InvalidMethodTest.suite
  suite << CircularReferenceTest.suite
  suite << AutomaticCustomMarshalllerTest.suite
end

def add_slow_automatic_tests(suite)
  suite << ThreadedStartupTest.suite
  suite << BasicThreadSafetyTest.suite
end

if __FILE__ == $0
  slowsuite = Test::Unit::TestSuite.new("AutomaticMadeleine (including slow tests)")
  add_automatic_tests(slowsuite)
  add_slow_automatic_tests(slowsuite)

  require 'test/unit/ui/console/testrunner'
  Test::Unit::UI::Console::TestRunner.run(slowsuite)
end
