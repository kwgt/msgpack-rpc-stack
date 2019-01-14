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
