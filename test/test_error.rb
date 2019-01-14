require 'test/unit'
require 'socket'
require './test/common'

require 'msgpack/rpc/server'
require 'msgpack/rpc/client'

class TestError < Test::Unit::TestCase
  TEST_PORT = 9001

  class Client
    include MessagePack::Rpc::Client
    include ClientBase
  end

  test "not callable procedure" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          class << self
            def que
              return (@que ||= Queue.new)
            end
          end

          msgpack_options :symbolize_keys => true

          def test
            return :OK
          end

          def on_error(msg)
            self.class.que << msg
          end
        }
      }

      assert_nothing_raised {
        server.up(TEST_PORT)
      }

      port = assert_nothing_raised {
        Client.open(TEST_PORT)
      }

      e = assert_raise {
        port.call(:test)
      }

      assert_equal("procedure `test` is not callable from remote", e.data)
      assert_equal("procedure `test` is not callable from remote",
                   server.que.deq)

    ensure
      port.close if port
      server.down if server
    end
  end

  test "unhandled notify #1" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          class << self
            def que
              return (@que ||= Queue.new)
            end
          end

          msgpack_options :symbolize_keys => true

          def test
            return :OK
          end

          def on_error(msg)
            self.class.que << msg
          end
        }
      }

      assert_nothing_raised {
        server.up(TEST_PORT)
      }

      port = assert_nothing_raised {
        Client.open(TEST_PORT)
      }

      assert_nothing_raised {
        port.notify(:test)
      }

      assert_equal("notify `test` is unhandled", server.que.deq)

    ensure
      port.close if port
      server.down if server
    end
  end

end
