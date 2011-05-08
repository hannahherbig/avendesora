#
# avendesora: malkier irc server
# lib/ircd.rb: startup routines, etc
#
# Copyright (c) 2010-2011 Eric Will <rakaur@malkier.net>
# Copyright (c) 2011 Michael Rodriguez <dkingston@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
require 'logger'
require 'optparse'
require 'yaml'

# Import required application modules
require 'ircd/config'
require 'ircd/loggable'
require 'ircd/server'

module IRC

# The main application class
class Application

    ##
    # mixins
    include Loggable

    ##
    # constants

    # Project name
    ME = 'ircd'

    # Version number
    V_MAJOR  = 0
    V_MINOR  = 1
    V_PATCH  = 0

    VERSION  = "#{V_MAJOR}.#{V_MINOR}.#{V_PATCH}"

    # Configuration data
    @@config = nil

    # A list of our servers
    @@servers = []

    ##
    # Create a new +Server+ object, which starts and runs the entire
    # application. Everything starts and ends here.
    #
    # return:: self
    #
    def initialize
        puts "#{ME}: version #{VERSION} [#{RUBY_PLATFORM}]"

        # Check to see if we're running on good rubies
        if RUBY_VERSION >= '1.8' && RUBY_VERSION < '1.8.7'
            puts "#{ME}: requires at lesat ruby 1.8.7"
            puts "#{ME}: you have #{RUBY_VERSION}"
            abort
        elsif RUBY_VERSION >= '1.9' && RUBY_VERSION < '1.9.2'
            puts "#{ME}: requires at least ruby 1.9.2"
            puts "#{ME}: you have #{RUBY_VERSION}"
            abort
        end

        # Check to see if we're running as root
        if Process.euid == 0
            puts "#{ME}: refuses to run as root"
            abort
        end

        # Some defaults for state
        logging  = true
        debug    = false
        willfork = RUBY_PLATFORM =~ /win32/i ? false : true
        wd       = Dir.getwd
        @logger  = nil

        # Do command-line options
        opts = OptionParser.new

        dd = 'Enable debug logging.'
        hd = 'Display usage information.'
        nd = 'Do not fork into the background.'
        qd = 'Disable regular logging.'
        vd = 'Display version information.'

        opts.on('-d', '--debug',   dd) { debug    = true  }
        opts.on('-h', '--help',    hd) { puts opts; abort }
        opts.on('-n', '--no-fork', nd) { willfork = false }
        opts.on('-q', '--quiet',   qd) { logging  = false }
        opts.on('-v', '--version', vd) { abort            }

        begin
            opts.parse(*ARGV)
        rescue OptionParser::ParseError => err
            puts err, opts
            abort
        end

        # Interpreter warnings
        $-w = true if debug

        # Signal handlers
        trap(:INT)   { app_exit }
        trap(:TERM)  { app_exit }
        trap(:PIPE)  { :SIG_IGN }
        trap(:CHLD)  { :SIG_IGN }
        trap(:WINCH) { :SIG_IGN }
        trap(:TTIN)  { :SIG_IGN }
        trap(:TTOU)  { :SIG_IGN }
        trap(:TSTP)  { :SIG_IGN }

        if debug
            puts "#{ME}: warning: debug mode enabled"
            puts "#{ME}: warning: all streams will be logged in the clear!"
        end

        # Check to see if we're already running
        if File.exists?('var/ircd.pid')
            curpid = nil
            File.open('var/ircd.pid', 'r') { |f| curpid = f.read.chomp.to_i }

            begin
                Process.kill(0, curpid)
            rescue Errno::ESRCH, Errno::EPERM
                File.delete('var/ircd.pid')
            else
                puts "#{ME}: daemon is already running"
                abort
            end
        end

        # Fork into the background
        if willfork
            begin
                pid = fork
            rescue Exception => e
                puts "#{ME}: cannot fork into the background"
                abort
            end

            # This is the child process
            unless pid
                Dir.chdir(wd)
                File.umask(0)
            else # This is the parent process
                puts "#{ME}: pid #{pid}"
                puts "#{ME}: running in background mode from #{Dir.getwd}"
                abort
            end

            [$stdin, $stdout, $stderr].each { |s| s.close }

            # Set up logging
            if logging or debug
                Dir.mkdir('var') unless File.exists?('var')
                self.logger = Logger.new('var/ircd.log', 'weekly')
            end
        else
            puts "#{ME}: pid #{Process.pid}"
            puts "#{ME}: running in foreground mode from #{Dir.getwd}"

            # Set up logging
            self.logger = Logger.new($stdout) if logging or debug
        end

        if debug
            log_level = :debug
        else
            log_level = @@config.log_level.to_sym
        end

        self.log_level = log_level if logging

        # Write the PID file
        Dir.mkdir('var') unless File.exists?('var')
        File.open('var/ircd.pid', 'w') { |f| f.puts(Process.pid) }

        # XXX - timers

        # Start the listeners (one IRC::Server per port)
        @@config.listeners.each do |listener|
            @@servers << IRC::Server.new do |s|
                s.bind_to = listener.bind_to
                s.port    = listener.port.to_i
                s.logger  = @logger
            end
        end

        Thread.abort_on_exception = true if debug

        @@servers.each { |s| s.thread = Thread.new { s.io_loop } }
        @@servers.each { |s| s.thread.join }

        # Exiting...
        app_exit

        # Return...
        self
    end

    #######
    private
    #######

    # Converts a Hash into a Hash that allows lookup by String or Symbol
    def indifferent_hash(hash)
        # Hash.new blocks catch lookup failures
        hash = Hash.new do |hash, key|
                   hash[key.to_s] if key.is_a?(Symbol)
               end.merge(hash)

        # Look for any hashes inside the hash to convert
        hash.each do |key, value|
            # Convert this subhash
            hash[key] = indifferent_hash(value) if value.is_a?(Hash)

            # Arrays could have hashes in them
            value.each_with_index do |arval, index|
                hash[key][index] = indifferent_hash(arval) if arval.is_a?(Hash)
            end if value.is_a?(Array)
        end
    end

    def app_exit
        @logger.close if @logger
        File.delete('var/ircd.pid')
        exit
    end
end

end # module IRC
