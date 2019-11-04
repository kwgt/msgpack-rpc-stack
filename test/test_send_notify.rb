require 'test/unit'
require 'timeout'
require './test/common'

require 'msgpack/rpc/server'
require 'msgpack/rpc/client'

class TestSendNotify < Test::Unit::TestCase
  TEST_PORT = 9001

  class Client
    include MessagePack::Rpc::Client
    include ClientBase
    include ClientBase::SyncCall
  end

  test "server to client" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          def test
            notify(:come, "hello", 1)
            return :OK
          end
          remote_public :test
        }
      }

      server.up(TEST_PORT)

      port = assert_nothing_raised {
        Client.open(TEST_PORT)
      }

      que  = Queue.new

      port.on(:come) { |a, b|
        que << [a, b]
      }

      assert_equal("OK", port.call(:test))

      resp = assert_nothing_raised {
        Timeout.timeout(10) {que.deq}
      }

      assert_equal(["hello", 1], resp)

    ensure
      port.close if port
      server.down if server
    end
  end

  test "client to server" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          def test
            notify(:come, "hello", 2)
          end
          remote_public :test
        }
      }

      server.up(TEST_PORT)

      port = assert_nothing_raised {
        Client.open(TEST_PORT)
      }

      que  = Queue.new

      port.on(:come) { |a, b|
        que << [a, b]
      }

      resp = assert_nothing_raised {
        port.notify(:test)
        Timeout.timeout(10) {que.deq}
      }

      assert_equal(["hello", 2], resp)

    ensure
      port.close if port
      server.down if server
    end
  end
end
