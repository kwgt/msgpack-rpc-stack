#! /usr/bin/env ruby
# coding: utf-8

require 'socket'
require 'msgpack/rpc/client'

class SampleClient
  include MessagePack::Rpc::Client

  class Exit < Exception; end

  class Error < Exception
    def initialize(data)
      @data = data
    end

    attr_reader :data
  end

  class << self
    def open(host, port)
      ret = self.allocate

      ret.instance_eval {
        @sock   = TCPSocket.open(host, port)
        @sock.sync

        @thread = Thread.fork {
          begin
            loop {
              # 受け取ったデータをMessagePack::Rpc::Client#receive_streamで
              # モジュールにデータを流し込む
              receive_stream(@sock.readpartial(1024))
            }

          rescue Exit
          end
        }
      }

      return ret
    end
  end

  def close
    @thread.raise(Exit)
    @thread.join
    @sock.close
  end

  #
  # require for MessagePack::Rpc::Server
  # 

  def send_data(data)
    @sock.write(data)
  end
  private :send_data
end

#
# main process
#

port = SampleClient.open("localhost", 9001)
que  = Queue.new

port.call(:foo) { |resp, error|
  que << [:foo, resp, error]
}

port.call(:bar) { |resp, error|
  que << [:bar, resp, error]
}

port.call(:baz) { |resp, error|
  que << [:baz, resp, error]
}

p que.deq
p que.deq
p que.deq

port.notify(:bye)
port.close
