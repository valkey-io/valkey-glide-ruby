# frozen_string_literal: true

module Lint
  module BitmapCommands
    def test_bitfield
      assert_equal [1, 0], r.bitfield('foo', 'INCRBY', 'i5', 100, 1, 'GET', 'u4', 0)
    end

    def test_bitfield_ro
      assert_equal [0], r.bitfield_ro('foo', 'GET', 'u4', 0)
    end

    def test_bitop
      r.set('foo{1}', 'a')
      r.set('bar{1}', 'b')

      r.bitop(:and, 'foo&bar{1}', 'foo{1}', 'bar{1}')
      assert_equal "\x60", r.get('foo&bar{1}')

      r.bitop(:and, 'foo&bar{1}', ['foo{1}', 'bar{1}'])
      assert_equal "\x60", r.get('foo&bar{1}')

      r.bitop(:or, 'foo|bar{1}', 'foo{1}', 'bar{1}')
      assert_equal "\x63", r.get('foo|bar{1}')
      r.bitop(:xor, 'foo^bar{1}', 'foo{1}', 'bar{1}')
      assert_equal "\x03", r.get('foo^bar{1}')
      r.bitop(:not, '~foo{1}', 'foo{1}')
      assert_equal "\x9E".b, r.get('~foo{1}')
    end

    def test_getbit
      r.set("foo", "a")

      assert_equal 1, r.getbit("foo", 1)
      assert_equal 1, r.getbit("foo", 2)
      assert_equal 0, r.getbit("foo", 3)
      assert_equal 0, r.getbit("foo", 4)
      assert_equal 0, r.getbit("foo", 5)
      assert_equal 0, r.getbit("foo", 6)
      assert_equal 1, r.getbit("foo", 7)
    end

    def test_setbit
      r.set("foo", "a")

      r.setbit("foo", 6, 1)

      assert_equal "c", r.get("foo")
    end

    def test_bitcount
      r.set("foo", "abcde")

      assert_equal 10, r.bitcount("foo", 1, 3)
      assert_equal 17, r.bitcount("foo", 0, -1)
    end

    def test_bitcount_bits_range
      target_version "7.0" do
        r.set("foo", "abcde")

        assert_equal 10, r.bitcount("foo", 8, 31, scale: :bit)
        assert_equal 17, r.bitcount("foo", 0, -1, scale: :byte)
      end
    end
  end
end
