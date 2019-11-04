require 'test/unit'
require 'socket'
require './test/common'

require 'msgpack/rpc/server'
require 'msgpack/rpc/client'

class TestProcedureCall< Test::Unit::TestCase
  TEST_PORT = 9001

  class Client
    include MessagePack::Rpc::Client
    include ClientBase
    include ClientBase::SyncCall
  end

  test "sync call" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          def test
            return "hello"
          end
          remote_public :test
        }
      }

      server.up(TEST_PORT)

      port = assert_nothing_raised {
        Client.open(TEST_PORT)
      }

      assert_equal("hello", port.call(:test))

    ensure
      port.close if port
      server.down if server
    end
  end

  test "async call" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          def test(df)
            sleep 2
            df.resolve("hello")
          end
          remote_async :test
        }
      }

      assert_nothing_raised {
        server.up(TEST_PORT)
      }

      port = assert_nothing_raised {
        Client.open(TEST_PORT)
      }

      assert_equal("hello", port.call(:test))

    ensure
      port.close if port
      server.down if server
    end
  end

  test "with argument #1" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          def test(a, b)
            return a * b
          end
          remote_public :test
        }
      }

      assert_nothing_raised {
        server.up(TEST_PORT)
      }

      port = assert_nothing_raised {
        Client.open(TEST_PORT)
      }

      assert_equal(10000, port.call(:test, 100, 100))

    ensure
      port.close if port
      server.down if server
    end
  end

  test "with argument #2" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          def test(h)
            return h["str"] * h["n"]
          end
          remote_public :test
        }
      }

      assert_nothing_raised {
        server.up(TEST_PORT)
      }

      port = assert_nothing_raised {
        Client.open(TEST_PORT)
      }

      assert_equal("abcabc", port.call(:test, {:str => "abc", :n => 2}))

    ensure
      port.close if port
      server.down if server
    end
  end
end
