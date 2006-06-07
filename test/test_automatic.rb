#!/usr/local/bin/ruby -w
#
# Copyright(c) 2003-2004 Stephen Sykes
# Copyright(c) 2003-2004 Anders Bengtsson
#

$LOAD_PATH.unshift("test")
require 'test_automatic_common'

class A
  include Madeleine::Automatic::Interceptor
  attr_accessor :z,:k
  def initialize
    @k=1
  end
end

class B
  include Madeleine::Automatic::Interceptor
  attr_accessor :yy, :s
  def initialize(a)
    @yy = C.new(a)
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

class K
  include Madeleine::Automatic::Interceptor
  attr_accessor :k
  def initialize
    @k=1
  end
  def seven
    @k=7
  end
  def fourteen
    @k=14
  end
  automatic_read_only :fourteen
  automatic_read_only
  def twentyone
    @k=21
  end
end  

class L
  include Madeleine::Automatic::Interceptor
  attr_reader :x
  def initialize
    @x = M.new(self)
  end
end

class M
  include Madeleine::Automatic::Interceptor
  attr_reader :yy
  def initialize(yy)
    @yy = yy
  end
end

class N < Hash
  include Madeleine::Automatic::Interceptor
end

# Basic test, and that system works in SAFE level 1
class BasicTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    simpletest(1)
  end

  def test_main_in_safe_level_one
    thread = Thread.new {
      $SAFE = 1
      test_main
    }
    thread.join
  end
end

class ObjectOutsideTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    mad = create_new_system(A, prevalence_base)
    assert_raises(RuntimeError) {
                 mad.system.z = A.new  # app object created outside system
               }
    mad.close
  end
end

# Passing a block when it would generate a command is not allowed because blocks cannot
# be serialised.  However, block passing/yielding inside the application is ok.
class BlockGivenTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    mad = create_new_system(J, prevalence_base)
    assert_raises(RuntimeError) {
                   mad.system.yielder {|a| a}
                 }
    mad.close
    mad2 = create_new_system(I, prevalence_base+"2")
    assert(mad2.system.testyield, "Internal block passing")
    mad2.close
  end
end

class NonPersistedObjectTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    mad_b = create_new_system(B, prevalence_base, 0)
    mad_b.system.yy.x -= 1
    assert_equal(-1, mad_b.system.yy.x, "Direct change of object inside main object")

    mad_b.system.yy.a.w ||= "hello"  # not saved
    mad_b.system.yy.a.w += " again"  # not saved

    assert_equal("hello again", mad_b.system.yy.a.w, "Non persisted object before close")

    mad_b.close
    mad_b2 = make_system(prevalence_base) { B.new(0) }
    assert_equal(nil, mad_b2.system.yy.a.w, "Non persisted object after restart, no snapshot")
    mad_b2.system.yy.a.w ||= "hello"  # not saved
    mad_b2.system.yy.a.w += " again"  # not saved
    mad_b2.take_snapshot             # NOW saved
    mad_b2.system.yy.a.w += " again"  # not saved
    assert_equal("hello again again", mad_b2.system.yy.a.w, "Non persisted object after take_snapshot and 1 change")

    mad_b2.close
    mad_b3 = make_system(prevalence_base) { B.new(0) }
    assert_equal("hello again", mad_b3.system.yy.a.w, "Non persisted object after restore (back to snapshotted state)")
    mad_b3.close
  end
end

class RefInExternalObjTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    mad_c = create_new_system(B, prevalence_base, 0)
    x = D.new
    x.w = mad_c.system.yy
    mad_c.system.s = x  # pass in an external object that contains a ref to obj in ths system

    mad_c.system.s.w.x += 1      # Increment counter via external obj
    assert_equal(1, mad_c.system.yy.x, "Change via external object")
    mad_c.system.yy.x += 1        # Increment counter directly
    assert_equal(2, mad_c.system.s.w.x, "Direct change")
    mad_c.close

    mad_c2 = make_system(prevalence_base) { B.new(0) }
    assert_equal(2, mad_c2.system.s.w.x, "Value via external object after commands/restore")
    assert_equal(2, mad_c2.system.yy.x, "Direct value after restore")
    mad_c2.take_snapshot
    mad_c2.close

    mad_c3 = make_system(prevalence_base) { B.new(0) }
    assert_equal(2, mad_c3.system.s.w.x, "Value via external object after snapshot/restore")
    assert_equal(2, mad_c3.system.yy.x, "Direct value after snapshot/restore")

    mad_c3.system.s.w.x += 1      # Increment counter via external obj
    mad_c3.system.yy.x += 1        # Increment counter directly
    mad_c3.close

    mad_c4 = make_system(prevalence_base) { B.new(0) }
    assert_equal(4, mad_c4.system.s.w.x, "Value via external object after snapshot+commands/restore")
    assert_equal(4, mad_c4.system.yy.x, "Direct value after snapshot+commands/restore")
    mad_c4.close
  end
end

class BasicThreadSafetyTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    x = Thread.new {
          simpletest(1)
        }
    y = Thread.new {
          simpletest(2)
        }
    x.join
    y.join
  end
end

class InvalidMethodTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    mad_f = create_new_system(A, prevalence_base)
    mad_f.system.z = -1
    assert_raises(NoMethodError) {
                   mad_f.system.not_a_method
                 }
    assert_equal(-1, mad_f.system.z, "System functions after NoMethodError")
    mad_f.close
  end
end

class CircularReferenceTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    mad_g = create_new_system(G, prevalence_base)
    mad_g.system.yy.w = mad_g.system
    mad_g.close
    mad_g2 = make_system(prevalence_base) { G.new }
    assert(mad_g2.system == mad_g2.system.yy.w.yy.w.yy.w, "Circular reference after command/restore")
    mad_g2.take_snapshot
    mad_g2.close
    mad_g3 = make_system(prevalence_base) { G.new }
    assert(mad_g3.system == mad_g3.system.yy.w.yy.w.yy.w, "Circular reference after snapshot/restore")
    mad_g3.system.yy.w.yy.w.yy.w.a = 1
    assert_equal(1, mad_g3.system.a, "Circular reference change")
    mad_g3.close
    mad_g4 = make_system(prevalence_base) { G.new }
    assert_equal(1, mad_g4.system.yy.w.yy.w.yy.w.a, "Circular reference after snapshot+commands/restore")
    mad_g4.close
# The following tests would fail, cannot pass self (from class L to class M during init)
# self is the proxied object itself, not the Prox object it needs to be
    mad_l = create_new_system(L, prevalence_base)
#    assert_equal(mad_l.system, mad_l.system.x.yy, "Circular ref before snapshot/restore, passed self")
    mad_l.take_snapshot
    mad_l.close
    mad_l = make_system(prevalence_base) { L.new }
#    assert_equal(mad_l.system, mad_l.system.x.yy, "Circular ref after snapshot/restore, passed self")
    mad_l.close
  end
end

class AutomaticCustomMarshallerTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    custom_m(YAML)
    custom_m(SOAP::Marshal)
    custom_m(Madeleine::ZMarshal.new)
    custom_m(Madeleine::ZMarshal.new(YAML))
    custom_m(Madeleine::ZMarshal.new(SOAP::Marshal))
  end

  def custom_m(marshaller)
    dir = prevalence_base
    delete_directory(dir)
    @system_bases << dir
    mad_h = make_system(dir) { G.new }
    mad_h.system.yy.w = "abc"
    mad_h.take_snapshot
    mad_h.system.yy.w += "d"
    assert_equal("abcd", mad_h.system.yy.w, "Custom marshalling after snapshot+commands with normal marshaller")
    mad_h.close
    mad_h = make_system(dir, marshaller) { G.new }
    assert_equal("abcd", mad_h.system.yy.w, "Custom marshalling after snapshot+commands with normal marshaller, read with custom as marshaller")
    mad_h.close
    mad_h = make_system(dir) { G.new }
    mad_h.marshaller = marshaller
    mad_h.system.yy.w += "e"
    assert_equal("abcde", mad_h.system.yy.w, "Custom marshalling after snapshot+commands+change marshaller+commands")
    mad_h.take_snapshot
    mad_h.close
    if (marshaller == YAML)
      File.open(dir + "/000000000000000000002.snapshot", "r") {|f|
        assert_equal(f.gets, "--- !ruby/object:Madeleine::Automatic::Prox \n", "Custom marshalling marshaller change check")
      }
    end
    mad_h = make_system(dir, marshaller) { G.new }
    assert_equal("abcde", mad_h.system.yy.w, 
                 "Custom marshalling after snapshot+commands+change marshaller+commands+snapshot+restore with normal marshaller")
    mad_h.system.yy.w += "f"
    mad_h.close
    mad_h = make_system(dir) { G.new }
    assert_equal("abcdef", mad_h.system.yy.w, "Custom marshalling snapshot custom+commands+restore normal")
    mad_h.take_snapshot
    mad_h.close
    mad_h = make_system(dir, marshaller) { G.new }
    assert_equal("abcdef", mad_h.system.yy.w, "Custom marshalling snapshot+restore custom")
    mad_h.take_snapshot
    mad_h.system.yy.w += "g"
    mad_h.close
    mad_h = make_system(dir, marshaller) { G.new }
    assert_equal("abcdefg", mad_h.system.yy.w, "Custom marshalling after restore normal snapshot custom+commands+restore custom")
    mad_h.system.yy.w = "abc"
    mad_h.close
    mad_h2 = make_system(dir, marshaller) { G.new }
    assert_equal("abc", mad_h2.system.yy.w, "Custom marshalling after commands/restore")
    mad_h2.take_snapshot
    mad_h2.close
    mad_h3 = make_system(dir, marshaller) { G.new }
    assert_equal("abc", mad_h3.system.yy.w, "Custom marshalling after snapshot/restore")
    mad_h3.system.yy.w += "d"
    mad_h3.close
    mad_h4 = make_system(dir, marshaller) { G.new }
    assert_equal("abcd", mad_h4.system.yy.w, "Custom marshalling after snapshot+commands/restore")
    mad_h4.close
    mad_h = make_system(dir, marshaller) { G.new }
    mad_h.system.yy.w = mad_h.system
    mad_h.close
    mad_h2 = make_system(dir, marshaller) { G.new }
    assert_equal(mad_h2.system, mad_h2.system.yy.w, "Custom marshalling after commands/restore, circular ref")
    mad_h2.take_snapshot
    mad_h2.close
    mad_h3 = make_system(dir, marshaller) { G.new }
    assert_equal(mad_h3.system, mad_h3.system.yy.w, "Custom marshalling after snapshot/restore, circular ref")
    mad_h3.system.yy.w = "sss"
    mad_h3.system.yy.w = mad_h3.system
    mad_h3.close
    mad_h4 = make_system(dir, marshaller) { G.new }
    assert_equal(mad_h4.system, mad_h4.system.yy.w, "Custom marshalling after snapshot+commands/restore, circular ref")
    mad_h4.close
  end
end

# tests restoring when objects get unreferenced and GC'd during restore
class FinalisedTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    mad = create_new_system(B, prevalence_base, 0)
    mad.system.yy = Array.new(200000)  # make ruby run GC
    mad.system.yy = Array.new(200000)  # must be a better way, but running GC.start from inside
    mad.system.yy = Array.new(50000)   # class B didn't work for me
    mad.close
    mad2 = make_system(prevalence_base) { B.new(0) }
    mad2.close
  end
end

class DontInterceptTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    mad = create_new_system(K, prevalence_base)
    mad.system.seven
    assert_equal(7, mad.system.k, "Object changes")
    mad.system.fourteen
    assert_equal(14, mad.system.k, "Object changes, not intercepted")
    mad.system.twentyone
    assert_equal(21, mad.system.k, "Object changes, not intercepted")
    mad.close
    mad_1 = make_system(prevalence_base) { K.new }
    assert_equal(7, mad_1.system.k, "Commands but no snapshot")
    mad_1.take_snapshot
    mad_1.close
    mad_2 = make_system(prevalence_base) { K.new }
    assert_equal(7, mad_2.system.k, "Snapshot but no commands")
    mad_2.system.k -= 6
    mad_2.system.k -= 3
    mad_2.system.fourteen
    mad_2.close
    mad_3 = make_system(prevalence_base) { K.new }
    assert_equal(-2, mad_3.system.k, "Snapshot and commands")
    mad_3.close
  end
end

class NoMethodsAddedTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    mad = create_new_system(N, prevalence_base)
    mad.system["a"] = 99
    mad.close    
  end
end
