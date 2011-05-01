#
# avendesora: malkier irc server
# lib/ircd/client.rb: represents an IRC client
#
# Copyright (c) 2010-2011 Eric Will <rakaur@malkier.net>
# Copyright (c) 2011 Michael Rodriguez <dkingston@malkier.net>
#
# encoding: utf-8

# Import required application modules
%w(event loggable).each { |m| require m }

module IRC

# Base class for IRC clients
class Client
    ##
    # mixins
    include Loggable

    ##
    # instance attributes
    attr_accessor :hostname, :ip_address, :nickname, :realname, :username

    def initialize
        # Our Logger object
        @logger     = nil
        self.logger = nil

        # If we have a block let it set up our instance attributes
        yield(self) if block_given?

        log(:debug, "new client on #{@server.bind_to}:#{@server.port}")

        self
    end

    #######
    private
    #######

    ######
    public
    ######

    def dead?
        @dead
    end
end

class LocalClient < Client
    ##
    # instance attributes
    attr_accessor :server, :socket

    def initialize
        # Is our socket dead?
        @dead = false

        # The Server they connected to
        @server = nil

        super
    end

    ######
    public
    ######

    def dead?
        @dead
    end
end

end # module IRC
