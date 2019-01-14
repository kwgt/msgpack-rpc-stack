#! /usr/bin/env ruby
# coding: utf-8

#
# module of MessagePack-RPC protocol stack
#
#   Copyright (C) 2017 Hiroshi Kuwagata <kgt9221@gmail.com>
#

require 'msgpack'

module MessagePack
  module Rpc
    class ProtocolError < StandardError
      def initialize(msg, data = nil)
        super(msg)
        @data = data
      end

      attr_reader :data
    end
  end
end
