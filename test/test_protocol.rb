require 'test/unit'
require 'socket'
require './test/common'
require 'pry'

require 'msgpack/rpc/server'
require 'msgpack/rpc/client'

class TimedQueue
  class Timeout < StandardError; end

  def initialize(tmo)
    @que  = []
    @tmo  = tmo
    @mon  = Monitor.new
    @cond = @mon.new_cond
  end

  def enq(obj)
    @mon.synchronize {
      @que << obj
      @cond.signal
    }
  end

  alias :push :enq
  alias :<< :enq

  def deq
    @mon.synchronize {
      @cond.wait(@tmo)
      raise(Timeout) if @que.empty?

      return @que.shift
    }
  end

  alias :shift :deq
end

class TestProtocol < Test::Unit::TestCase
  TEST_PORT = 9001

  class Exit < Exception; end

  class Client
    include MessagePack::Rpc::Client
    include ClientBase

    def hook(&blk)
      @error_handler = blk

      def self.on_error(e)
        @error_handler.(e)
      end
    end
  end

  test "unknown response #1" do
    thread = Thread.new {
      begin
        serv = TCPServer.open(TEST_PORT)
        sock = serv.accept
        sock.write([1, 100, :test, nil].to_msgpack)
        sock.flush
        sleep

      rescue Exit
        sock.close
        serv.close
      end
    }

    sleep 1

    que  = TimedQueue.new(1)
    port = Client.open(TEST_PORT)
    port.hook { |e|
      que << e
    }

    assert_raise_kind_of(MessagePack::Rpc::ProtocolError) {
      raise(que.deq)
    }

    port.close
    thread.raise(Exit)
    thread.join
  end

  test "invalid response #1" do
    thread = Thread.new {
      begin
        serv = TCPServer.open(TEST_PORT)
        sock = serv.accept
        upk  = MessagePack::Unpacker.new(sock)

        upk.each { |pkt|
          if pkt[0] == 0
            sock.write([1, pkt[1], 0, 0].to_msgpack)
            sock.flush
          end
        }

      rescue Exit
        sock.close
        serv.close
      end
    }

    sleep 1

    que  = TimedQueue.new(1)
    port = Client.open(TEST_PORT)
    port.hook { |e|
      que << e
    }

    #binding.pry
    port.call(:test, 0) {}

    assert_raise_kind_of(MessagePack::Rpc::ProtocolError) {
      raise(que.deq)
    }

    port.close
    thread.raise(Exit)
    thread.join
  end

  test "cancel message" do
    thread = Thread.new {
      begin
        serv = TCPServer.open(TEST_PORT)
        sock = serv.accept
        upk  = MessagePack::Unpacker.new(sock)

        upk.each { |pkt|
          if pkt[0] == 0
            sleep 2
            sock.write([1, pkt[1], :test, nil].to_msgpack)
            sock.flush
          end
        }

      rescue Exit
        sock.close
        serv.close
      end
    }

    sleep 1

    route = []
    que1  = TimedQueue.new(1)
    que2  = TimedQueue.new(1)
    port  = Client.open(TEST_PORT)

    port.hook { |e|
      route << :cp1
      que2 << e
    }

    begin
      #binding.pry
      route << :cp2
      id = port.call(:test) { |res, err|
        route << :cp3
        que1 << res
      }

      route << :cp4
      que1.deq

      que2 << "not reach"
      route << :cp5

    rescue => e
      assert_kind_of(TimedQueue::Timeout, e)
      port.cancel(id)
      route << :cp6
    end

    e = que2.deq
    assert_kind_of(MessagePack::Rpc::ProtocolError, e)
    assert_equal("unknwon responce id is received.", e.message)

    assert_equal([:cp2, :cp4, :cp6, :cp1], route)

    port.close
    thread.raise(Exit)
    thread.join
  end
end
