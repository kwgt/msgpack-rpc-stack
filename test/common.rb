require 'socket'

module ServerBase
  class Exit < Exception; end

  class << self
    def included(klass)
      class << klass
        def up(port)
          @server = TCPServer.open(port)
          @thread = Thread.new {
            loop {
              begin
                sock = @server.accept
                self.new(sock)

              rescue Exit
                break
              end
            }
          }
        end

        def down
          @thread.raise(Exit)
          @thread.join
          @server.close
        end
      end
    end
  end

  def initialize(sock)
    @sock = sock

    Thread.new {
      receive_stream(@sock.readpartial(1024)) until @sock.eof?
      @sock.close
    }
  end

  def send_data(data)
    @sock.write(data)
  end
  private :send_data
end

module ClientBase
  class Exit < Exception; end

  class Error < Exception
    def initialize(data)
      @data = data
    end

    attr_reader :data
  end

  class << self
    def included(klass)
      class << klass
        undef :new

        def open(port)
          ret = self.allocate

          ret.instance_eval {
            @sock   = TCPSocket.open("localhost", port)
            @que    = Queue.new

            @sock.sync

            @thread = Thread.fork {
              begin
                loop {receive_stream(@sock.readpartial(1024))}

              rescue Exit
              end
            }
          }

          return ret
        end
      end
    end
  end

  def close
    @thread.raise(Exit)
    @thread.join
    @sock.close
  end

  def send_data(data)
    @sock.write(data)
  end
  private :send_data

  def call(meth, *args)
    super(meth, *args) {|ret, err| @que << (ret || Error.new(err))}

    ret = @que.deq

    raise(ret) if ret.kind_of?(Error)

    return ret
  end
end
