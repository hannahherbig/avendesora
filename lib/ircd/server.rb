#
# avendesora: malkier irc server
# lib/ircd/server.rb: acts as a TCP server
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
require 'socket'

# Import required application modules
%w(client event loggable).each { |m| require 'ircd/' + m }

module IRC

# This class acts as a TCP server and handles all clients connected to it
class Server
    ##
    # mixins
    include Loggable

    ##
    # instance attributes
    attr_accessor :bind_to, :port, :thread
    attr_reader   :socket

    ##
    # Creates a new +IRC::Server+ that listens for client connections.
    # If given a block, it passes itself to the block for setting attributes.
    #
    def initialize
        # A list of our connected clients
        @clients = []

        # Is our socket dead?
        @dead = false

        # Our event queue
        @eventq = EventQueue.new

        # Our Logger object
        @logger     = nil
        self.logger = nil

        # If we have a block let it set up our instance attributes
        yield(self) if block_given?

        log(:debug, "new server at #@bind_to:#@port")

        # Start up the listener
        start_listening

        # Set up event handlers
        set_default_handlers

        self
    end

    #######
    private
    #######

    def start_listening
        begin
            if @bind_to == '*'
                @socket = TCPServer.new(@port)
            else
                @socket = TCPServer.new(@bind_to, @port)
            end
        rescue Exception => e
            log(:fatal, "error acquiring socket for #@bind_to:#@port")
            raise
        else
            log(:info, "server listening at #@bind_to:#@port")
            @dead = false
        end
    end

    ##
    # Sets up some default event handlers to track various states and such.
    # ---
    # returns:: +self+
    #
    def set_default_handlers
        @eventq.handle(:dead)       { start_listening }
        @eventq.handle(:connection) { new_connection  }
    end

    def new_connection
        begin
            newsock = @socket.accept_nonblock
        rescue IO::WaitReadable
            return
        end

        # This is to get around some silly IPv6 stuff
        host = newsock.peeraddr[3].sub('::ffff:', '')

        log(:info, "#@bind_to:#@port: new connection from #{host}")

        @clients << LocalClient.new do |c|
            c.hostname = host
            c.logger   = @logger
            c.server   = self
            c.socket   = newsock
        end
    end

    ######
    public
    ######

    def dead?
        @dead
    end

    def io_loop
        loop do
            # Is our server's listening socket dead?
            if dead?
                log(:warning, "listener has died on #@host:#@port, restarting")
                @socket.close
                @socket = nil
                @eventq.post(:dead)
            end

            # Run the event loop. These events will add IO, and possibly other
            # events, so we keep running until it's empty.
            @eventq.run while @eventq.needs_ran?

            readfds  = [@socket]
            writefds = []

            ret = IO.select(readfds, writefds, nil, nil)

            next unless ret

            # readfds
            ret[0].each do |socket|
                if socket == @socket
                    @eventq.post(:connection)
                else
                    @eventq.post(:read_ready, socket)
                end
            end unless ret[0].empty?

            # writefds
            ret[1].each do |socket|
                @eventq.post(:write_ready, socket)
            end unless ret[1].empty?
        end
    end
end

end # module IRC
