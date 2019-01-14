# msgpack-rpc-stack
A module of implementation for MessagePack-RPC protocol stack.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'msgpack-rpc-stack'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install msgpack-rpc-stack

## Example

### server side

#### with EventMachine

```ruby
#! /usr/bin/env ruby
# coding: utf-8
require 'logger'

require 'eventmachine'
require 'msgpack/rpc/server'

$logger = Logger.new(STDOUT)
$logger.datetime_format = "%Y-%m-%dT%H:%M:%S"

class RpcServer < EM::Connection
  include MessagePack::Rpc::Server

  # EM::Connection#receive_dataをMessagePack::Rpc::Server#receive_streamの
  # aliasにすることによって自動的にデータが流し込まれるようにしている。
  alias :receive_data :receive_stream

  def post_init
    info = Socket.unpack_sockaddr_in(get_peername())

    @addr = info[1]
    @port = info[0]

    $logger.info("connection from #{@addr}:#{@port}")
  end

  def unbind
    $logger.info("connection close #{@addr}:#{@port}")
  end

  #
  # require for MessagePack::Rpc::Server
  #

  # send_dataメソッドはEM::Connectionで提供されるので定義なし

  def on_error(msg)
    $logger.error(msg)
  end

  #
  # declar procedure
  #

  def bar
    $logger.info("call `bar` from #{@addr}:#{@port}")
    return "hello"
  end
  remote_public :bar

  def foo(df)
    $logger.info("call `foo` from #{@addr}:#{@port}")
    EM.defer {
      sleep 3
      df.resolve("timeout")
    }
  end
  remote_async :foo

  def bye
    $logger.info("receive notify `bye` from #{@addr}:#{@port}")
    EM.stop
  end
  remote_public :bye
end

#
# main process
#

EM.run {
  $logger.info("start dummy server")
  EM.start_server("localhost", 9001, RpcServer)
}
```

#### use raw TCP socket
```ruby
require 'logger'
require 'socket'
require 'msgpack/rpc/server'

$logger = Logger.new(STDOUT)
$logger.datetime_format = "%Y-%m-%dT%H:%M:%S"

#
# 簡略化のため、個別にスレッドを立ち上げる実装にしています。本来であれば、
# いちいちスレッドを立ち上げるのはリソースがもったいないので、ちゃんとし
# たコードを書く場合はIO.selectで多重化するようにして下さい。
#

class Server
  include MessagePack::Rpc::Server

  class Exit < Exception; end

  class << self
    def up(host, port)
      $logger.info("start dummy server")

      @server = TCPServer.open(host, port)
      @thread = Thread.current
      loop {
        begin
          sock = @server.accept
          self.new(sock)

        rescue Exit
          break
        end
      }
    end

    def down
      @thread.raise(Exit)
      @thread.join
      @server.close
      $logger.info("stop dummy server")
    end
  end
  
  def initialize(sock)
    @sock = sock

    info  = @sock.peeraddr
    @addr = info[2]
    @port = info[1]

    $logger.info("connection from #{@addr}:#{@port}")

    Thread.new {
      until @sock.eof?
        # 受け取ったデータをMessagePack::Rpc::Server#receive_streamで
        # モジュールにデータを流し込む
        receive_stream(@sock.readpartial(1024))
      end
       
      $logger.info("connection close #{@addr}:#{@port}")
      @sock.close
    }
  end

  #
  # require for MessagePack::Rpc::Server
  #

  def send_data(data)
    @sock.write(data)
  end
  private :send_data

  def on_error(msg)
    $logger.error(msg)
  end
  private :on_error
  
  #
  # declar procedures
  #

  def bar
    $logger.info("call `bar` from #{@addr}:#{@port}")
    return "hello"
  end
  remote_public :bar

  def foo(df)
    $logger.info("call `foo` from #{@addr}:#{@port}")
    Thread.new {
      sleep 3
      df.resolve("timeout")
    }
  end
  remote_async :foo

  def bye
    $logger.info("receive notify `bye` from #{@addr}:#{@port}")
    self.class.down
  end
  remote_public :bye
end

#
# main process
#

Server.up("localhost", 9001)
```

### client side

```ruby
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
  # require for MessagePack::Rpc::Client
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
```
