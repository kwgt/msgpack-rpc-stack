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
