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
    include ClientBase::SyncCall
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

          def on_error(e)
            self.class.que << e.message
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

          def on_error(e)
            self.class.que << e.message
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

  test "error return #1" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          def test
            raise("stop")
          end
          remote_public :test

          def on_error(e)
            # ignore
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

      assert_equal("stop", e.data)

    ensure
      port.close if port
      server.down if server
    end
  end

  test "error return #2" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          class Error < StandardError
            def initialize(data)
              @data = data
            end

            # エラー用のクラスはdataメソッドがあればその内容を
            # エラーデータとして送り返す
            # (dataメソッドが無い場合はmessageを送り返す)
            attr_reader :data
          end

          def test
            raise Error.new([0, 2, 3, 4])
          end
          remote_public :test

          def on_error(e)
            # ignore
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

      assert_equal([0, 2, 3, 4], e.data)

    ensure
      port.close if port
      server.down if server
    end
  end

  test "error return #3" do
    begin
      server = assert_nothing_raised {
        Class.new {
          include MessagePack::Rpc::Server
          include ServerBase

          def test(df)
            Thread.fork {
              sleep(2)
              df.reject([0, 2, 3, 4])
            }
          end
          remote_async :test

          def on_error(e)
            # ignore
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

      assert_equal([0, 2, 3, 4], e.data)

    ensure
      port.close if port
      server.down if server
    end
  end
end
