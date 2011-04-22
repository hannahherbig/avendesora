#
# avendesora: malkier irc server
# lib/ircd/config.rb: configuration DSL
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

require 'ostruct'

def configure(&block)
    IRC::Application.config = IRC::Application::Configuration.new
    IRC::Application.config.instance_eval(&block)
    IRC::Application.config.verify
    IRC::Application.new
end

module IRC

class Application
    @@config = nil

    def Application.config; @@config; end
    def Application.config=(config); @@config = config; end

    class Configuration
        attr_reader :listeners, :log_level, :name, :opers

        def initialize(&block)
            @log_level = :info
            @listeners = []
            @name      = nil
            @operators = []
        end

        def verify
            unless @name and @listeners.length > 0
                abort('ircd: invalid configuration')
            end
        end

        def logging(level)
            @log_level = level.to_s
        end

        def name(name)
            @name = name.to_s
        end

        def listen(port, host = '*')
            listener         = OpenStruct.new
            listener.port    = port.to_i
            listener.bind_to = host.to_s

            @listeners << listener
        end

        def operator(name, opts = {}, &block)
            oper       = OpenStruct.new
            oper.name  = name.to_s
            oper.flags = opts[:flags]

            oper.extend(ConfigOper)
            oper.instance_eval(&block)

            @operators << oper
        end

        module ConfigOper
            def password(password)
                self.password = password
            end
        end
    end
end

end # module IRC
