#
# Copyright(c) 2003-2004 Stephen Sykes
# Copyright(c) 2003-2004 Anders Bengtsson
#
# Common classes for test_automatic.rb and test_automatic_slow.rb
#

$LOAD_PATH.unshift("lib")
require 'madeleine'
require 'madeleine/automatic'
require 'test/unit'
#require 'contrib/batched.rb' # uncomment if testing batched

class F
  include Madeleine::Automatic::Interceptor
  attr_accessor :z,:a
  def plus1
    @z += 1
  end
end

class G
  include Madeleine::Automatic::Interceptor
  attr_accessor :yy,:a
  def initialize
    @yy = H.new
  end
end

class H
  include Madeleine::Automatic::Interceptor
  attr_accessor :w
  def minus1
    @w -= 1
  end
end


module AutoTest

  def persister
    SnapshotMadeleine
  end

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
    make_system(dir) { klass.new(*arg) }
  end

  def make_system(dir, marshaller=Marshal, &block)
    AutomaticSnapshotMadeleine.new(dir, marshaller, persister, &block)
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

  def simpletest(n)
    pb = prevalence_base + n.to_s
    mad_a = create_new_system(A, pb)
    mad_a.close
    mad_a1 = make_system(pb) { A.new }
    assert_equal(1, mad_a1.system.k, "No commands or snapshot")
    mad_a1.system.z = 0
    mad_a1.system.z += 1
    assert_equal(1, mad_a1.system.z, "Object changes")
    mad_a1.system.z -= 10
    assert_equal(-9, mad_a1.system.z, "Object changes")
    mad_a1.close
    mad_a2 = make_system(pb) { A.new }
    assert_equal(-9, mad_a2.system.z, "Commands but no snapshot")
    mad_a2.take_snapshot
    mad_a2.close
    mad_a3 = make_system(pb) { A.new }
    assert_equal(-9, mad_a3.system.z, "Snapshot but no commands")
    mad_a3.system.z -= 6
    mad_a3.system.z -= 3
    mad_a3.close
    mad_a4 = make_system(pb) { A.new }
    assert_equal(-18, mad_a4.system.z, "Snapshot and commands")
    mad_a4.close
  end
end
