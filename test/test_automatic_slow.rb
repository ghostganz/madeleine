#
# Copyright(c) 2003-2004 Stephen Sykes
# Copyright(c) 2003-2004 Anders Bengtsson
#
# Slow-running tests that are not part of the main (test.rb)
# test suite.
#

$LOAD_PATH.unshift("test")
require 'test_automatic_common'

class ThreadConfidenceTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    mad_d = create_new_system(F, prevalence_base)
    mad_d.system.z = 0
    mad_e = create_new_system(G, prevalence_base+"2")
    mad_e.system.yy.w = 0

    x = []
    25.times {|n|
      x[n] = Thread.new {
               5.times {
                 sleep(rand/10)
                 mad_d.system.plus1
                 mad_e.system.yy.minus1
               }
           }
    }
    25.times {|n|
      x[n].join
    }
    assert_equal(125, mad_d.system.z, "125 commands")
    assert_equal(-125, mad_e.system.yy.w, "125 commands")

    mad_e.close
    mad_e2 = make_system(prevalence_base+"2") { G.new }

    25.times {|n|
      x[n] = Thread.new {
               5.times {
                 sleep(rand/10)
                 mad_d.system.plus1
                 mad_e2.system.yy.minus1
               }
           }
    }
    25.times {|n|
      x[n].join
    }
    assert_equal(250, mad_d.system.z, "restore/125 commands")
    assert_equal(-250, mad_e2.system.yy.w, "restore/125 commands")
    mad_d.close
    mad_e2.close
  end
end

# tests thread safety during system creation, particularly that different system ids are generated
class ThreadedStartupTest < Test::Unit::TestCase
  include AutoTest

  def test_main
    x,mad = [],[]
    20.times {|n|
      x[n] = Thread.new {
               sleep(rand/100)
               mad[n] = create_new_system(F, prevalence_base+n.to_s)
               mad[n].system.z = n
               assert_equal(n, mad[n].system.z, "object change mad[#{n}].z")
               mad[n].close
             }
    }
    20.times {|n|
      x[n].join
      mad_i = make_system(prevalence_base+n.to_s) { F.new }
      assert_equal(n, mad_i.system.z, "restored mad[#{n}].z")
      mad_i.close
    }
  end
end
