require 'test/unit'
require 'socket'
require './test/common'

require 'msgpack/rpc/server'
require 'msgpack/rpc/client'

class TestSymbolize < Test::Unit::TestCase
  TEST_PORT = 9001

  class Client
    include MessagePack::Rpc::Client
    include ClientBase
  end

  test "procedure's argument" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          msgpack_options :symbolize_keys => true

          def test(h)
            return h[:str] * h[:n]
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
