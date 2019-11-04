#! /usr/bin/env ruby
# coding: utf-8

#
# module of MessagePack-RPC protocol stack
#
#   Copyright (C) 2017 Hiroshi Kuwagata <kgt9221@gmail.com>
#

require 'msgpack'
require 'msgpack/rpc'

module MessagePack
  module Rpc
    module Client
      class << self
        def included(klass)
          m = Module.new {
            klass.instance_variable_set(:@msgpack_options, {}) 

            def msgpack_options(opts = :none)
              if opts.nil? || opts.kind_of?(Hash)
                @msgpack_options = opts
              end

              return (@msgpack_options = opts)
            end

            def new_unpacker
              return MessagePack::Unpacker.new(@msgpack_options || {})
            end
          }

          klass.extend(m)
        end
      end

      def new_id
        @session_id ||= -1
        return (@session_id += 1)
      end
      private :new_id

      def session_map
        return (@session_map ||= {})
      end
      private :session_map

      def notify_handler
        return (@notify_handler ||= {})
      end
      private :notify_handler

      def unpacker
        return (@unpacker ||= self.class.new_unpacker)
      end
      private :unpacker

      def error_occured(e)
        e = ProtocolError.new(e) if e.kind_of?(String)

        if self.respond_to?(:on_error, true)
          __send__(:on_error, e)
        else
          STDERR.print("#{e.message}")
        end
      end
      private :error_occured

      def call(meth, *args, &blk)
        raise ArgumentError.new("handler is not spcified") if not blk

        id = new_id

        session_map[id] = blk
        send_data([0, id, meth, args].to_msgpack)

        return id
      end

      def notify(meth, *args)
        send_data([2, meth, args].to_msgpack)
      end

      def cancel(id)
        session_map.delete(id)
      end

      def eval_response(resp)
        if not resp.kind_of?(Array)
          error_occured("responce is not array")
        end

        case resp.shift
        when 1 # as response
          id, error, result = resp

          if not session_map.include?(id)
            error_occured("unknwon responce id is received.")

          elsif error.nil?
            # when success
            session_map.delete(id).(result, nil)

          elsif result.nil?
            # when error occurred
            session_map.delete(id).(nil, error)

          else
            session_map.delete(id)
            error_occured("invalid responce data")
          end

        when 2 # as notification
          meth = resp[0].to_sym
          args = resp[1]

          if notify_handler.include?(meth)
            notify_handler[meth].(*args)

          else
            STDERR.print("unhandled notification '#{meth}' received.\n")
          end

        else
          error_occured("unknown response received")
        end
      end
      private :eval_response

      def receive_dgram(data)
        eval_response(MessagePack.unpack(data, self.class.msgpack_options))
      end

      def receive_stream(data)
        begin
          unpacker.feed_each(data) {|resp| eval_response(resp)}

        rescue MessagePack::UnpackError => e
          unpacker.reset
          error_occured(e)

        rescue => e
          error_occured(e)
        end
      end

      def on(name, &blk)
        raise ArgumentError.new("handler is not spcified") if not blk
        notify_handler[name] = blk
      end
    end
  end
end
