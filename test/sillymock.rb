#
# Copyright (c) Anders Bengtsson 2004
#
# SillyMock is a simple tool for creating Mock objects
# for unit testing with Test::Unit.
#

require 'test/unit'

class Expectation

  def initialize(method, args=nil)
    @method = method
    @args = args
    @value = nil
    @been_called = false
  end

  def matches?(method, args=nil)
    if @method != method
      return false
    end
    if @args.nil?
      return true
    end
    @args == args
  end

  def matches_argument_count?(args)
    if @args.nil?
      return true
    end
    @args.size == args.size
  end

  def matches_method?(method)
    @method == method
  end

  def return_value(value)
    @value = value
  end

  def return(*args)
    @been_called = true
    unless @args.nil?
      if args.size != @args.size
        raise ArgumentError
      end
      if args != @args
        raise "hell 2"
      end
    end
    @value
  end

  def fulfilled?
    @been_called
  end
end


class Mock

  def initialize
    @expected = []
  end

  def expects(method, args=nil)
    expectation = Expectation.new(method, args)
    @expected << expectation
    expectation
  end

  def verify
    if @expected.detect {|e| not e.fulfilled? }
      raise Test::Unit::AssertionFailedError.new("had expectations...")
    end
  end

  def method_missing(name, *args)
    method_matching = @expected.select {|e| e.matches_method?(name) }
    if method_matching.empty?
      super
    end
    method_matching = method_matching.select {|e| e.matches_argument_count?(args) }
    if method_matching.empty?
      raise ArgumentError
    end
    expectation = method_matching.detect {|e| e.matches?(name, args) }
    if expectation
      expectation.return(*args)
    else
      raise "wrong arguments"
    end
  end
end
