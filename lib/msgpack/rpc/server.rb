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

    #
    # Module that implemented server protocol of MessagePack-RPC.
    # 
    # @abstract
    #   Include from the class that implements the rpc server. You can expose
    #   When the client implementation class receives data from the
    #   communication line, it must call the receive_data() method and pass
    #   received data to the MessagePack::Rpc::Server module.
    #   Also, the client implementation class should define a method
    #   send_data() to actually send the data. Call this method from
    #   within the MessagePack::Rpc::Server module if necessary
    #   (Implement send_data() method to accept string objects in arguments).
    #   If you receive a protocol level error, override the on_error() method.
    #   the methods defined in that class as RPC procedures.
    #
    module Server
      class << self
        #
        # @!method msgpack_options(**opts)
        #   set MessagePack::Unpacker option.
        #
        #   @example set :symbolize_keys option
        #     class Server
        #       include MessagePack::Rpc::Server
        #
        #       msgpack_options = {:symbolize_keys => true}
        #
        #       def test(data)
        #         # data's key are symbolized.
        #         return data[:data]
        #       end
        #       remote_public :test
        #     end

        #
        # @!method remote_public(name)
        #   expose syncronous procedure.
        #   The return value of the method exposed by this method is the 
        #   return value of the procedure. If an exception occurs, the
        #   exception is returned as an error value.
        #
        #   @param [Symbol] name
        #     target method name.
        #
        #   @example expose syncronous procedure
        #     class Server
        #       include MessagePack::Rpc::Server
        #
        #       def test(id)
        #         raise("id isnot defined") if id.nil?
        #         return "hello #{id}"
        #       end
        #       remote_public :test
        #     end
        #

        #
        # @!method remote_async(name)
        #   expose asynchronous procedure.
        #   The method exposed by this method takes a deferred object as its
        #   first argument. Returns the processing result asynchronously
        #   through this object.
        #
        #   @param [Symbol] name
        #     target method name.
        #
        #   @example expose asyncronous procedure
        #     class Server
        #       include MessagePack::Rpc::Server
        #
        #       def test(df, id)
        #         if id.nil?
        #           df.reject("id isnot defined")
        #         else
        #           df.resolve("hello #{id}")
        #         end
        #       end
        #       remote_async :test
        #     end
        #

        # @!visibility protected
        def included(klass)
          m = Module.new {
            @@error = Class.new(StandardError) {
              def initialize(label, data)
                super("error ocurred on precedure \"#{label}\"")
                @data = data
              end

              attr_reader :data
            }

            @@deferred = Class.new {
              def initialize(id, klass)
                @id    = id
                @klass = klass
              end

              def resolve(result)
                packet = [1, @id, nil, result].to_msgpack
                @klass.instance_eval {send_data(packet)}

                class << self
                  undef_method :resolve, :reject
                end
              end

              def reject(error)
                packet = [1, @id, error, nil].to_msgpack
                @klass.instance_eval {
                  send_data(packet)

                  if not error.kind_of?(Exception)
                    label = caller_locations(3..3)[0].base_label
                    error = @@error.new(label, error)
                  end

                  error.set_backtrace(caller(3..-1))
                  error_occured(error)
                }

                class << self
                  undef_method :resolve, :reject
                end
              end
            }

            klass.instance_variable_set(:@remote_public, [])
            klass.instance_variable_set(:@remote_async, [])
            klass.instance_variable_set(:@msgpack_options, {})

            def remote_public(meth = nil)
              @remote_public << meth if meth
              return @remote_public
            end

            def remote_async(meth = nil)
              @remote_async << meth if meth
              return @remote_async
            end

            def msgpack_options(opts = :none)
              if opts.nil? || opts.kind_of?(Hash)
                @msgpack_options = opts
              end

              return @msgpack_options
            end

            def new_unpacker
              return MessagePack::Unpacker.new(@msgpack_options || {})
            end
          }

          klass.extend(m)
        end
      end

      def unpacker
        return (@unpacker ||= self.class.new_unpacker)
      end

      def reset_unpacker
        @unpacker = nil
      end

      def do_async_call(id, meth, para)
        deferred = @@deferred.new(id, self)

        if not para
          self.__send__(meth, deferred)

        elsif para.kind_of?(Array)
          self.__send__(meth, deferred, *para)

        else
          self.__send__(meth, deferred, para)
        end
      end
      private :do_async_call

      def do_call(id, meth, para)
        if not para
          ret = self.__send__(meth)

        elsif para.kind_of?(Array)
          ret = self.__send__(meth, *para)

        else
          ret = self.__send__(meth, para)
        end

        return ret
      end
      private :do_call

      def do_notify(meth, para)
        if para.kind_of?(Array)
          self.__send__(meth.to_sym, *para)

        else
          self.__send__(meth.to_sym, para)
        end
      end
      private :do_notify

      def error_occured(e)
        if self.respond_to?(:on_error, true)
          __send__(:on_error, e)
        else
          STDERR.print("#{e.message}")
        end
      end
      private :error_occured

      def eval_message(msg)
        case msg[0]
        when 0
          #
          # when call
          #
          id   = msg[1]
          meth = msg[2].to_sym
          args = msg[3]

          if self.class.remote_async.include?(meth)
            do_async_call(id, meth, args)

          elsif self.class.remote_public.include?(meth)
            result = do_call(id, meth, args)
            send_data([1, id, nil, result].to_msgpack)

          else
            raise("procedure `#{meth}` is not callable from remote")
          end

        when 2
          #
          # when notify
          #
          meth = msg[1].to_sym
          args = msg[2]

          if self.class.remote_public.include?(meth)
            do_notify(meth, args);

          else
            raise("notify `#{meth}` is unhandled")
          end

        else
          raise ProtocolError.new("unknown message type #{msg[0]} recived.")
        end

      rescue => e
        if msg[0] == 0
          error = e.data rescue String.new(e.message, encoding:"UTF-8")
          send_data([1, id, error, nil].to_msgpack)
        end

        error_occured(e)
      end
      private :eval_message

      #
      # send the notification to peer rpc client
      #
      # @param [Symbol] meth
      #   notify name
      #
      # @param [Array] args
      #   argument for notification
      #
      def notify(meth, *args)
        send_data([2, meth, args].to_msgpack)
      end

      #
      # emqueu the received datagram to communication buffer
      #
      # @param [Blob] data
      #   recevied data from peer rpc client.
      #
      # @note
      #   Use this method for datagram communication.
      #   Use it when it is guaranteed that data is exchanged
      #   in packets (it works a bit faster).
      #
      def receive_dgram(data)
        msg = MessagePack.unpack(data, self.class.msgpack_options)

        if not msg.kind_of?(Array)
          error_occured(RantimeError.new("not array message is received"))
        end

        eval_message(msg)
      end

      #
      # emqueu the received data to communication buffer
      #
      # @param [Blob] data
      #   recevied data from peer rpc client.
      #
      def receive_stream(data)
        begin
          unpacker.feed_each(data) {|msg| eval_message(msg)}

        rescue MessagePack::UnpackError => e
          unpacker.reset
          error_occured(e)

        rescue => e
          error_occured(e)
        end
      end
    end
  end
end
