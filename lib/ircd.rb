#
# avendesora: malkier irc server
# lib/ircd.rb: startup routines, etc
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(logger optparse yaml).each { |m| require m }

# Import required application modules
%w(loggable).each { |m| require 'ircd/' + m }

module IRC

# The main application class
class Server

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

    ##
    # Create a new +Server+ object, which starts and runs the entire
    # application. Everything starts and ends here.
    #
    # return:: self
    #
    def initialize
        puts "#{ME}: version #{VERSION} [#{RUBY_PLATFORM}]"

        # Check to see if we're running on 1.9
        if RUBY_VERSION < '1.9.1'
            puts "#{ME}: requires at least ruby 1.9.1"
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

        # Load configuration file
        begin
            @@config = YAML.load_file('etc/config.yml')
        rescue Exception => e
            puts '----------------------------'
            puts "#{ME}: configure error: #{e}"
            puts '----------------------------'
            abort
        else
            keys_to_sym!(@@config)
        end

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
                Dir.mkdir('var') unless Dir.exists?('var')
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
            log_level = @@config[:logging].to_sym
        end

        self.log_level = log_level if logging

        # Write the PID file
        Dir.mkdir('var') unless Dir.exists?('var')
        File.open('var/ircd.pid', 'w') { |f| f.puts(Process.pid) }

        # XXX - timers

        # XXX - Start the listeners
        log(:info, 'started up')
        log(:debug, 'debugging!')

        # Exiting...
        app_exit

        # Return...
        self
    end

    #######
    private
    #######

    ##
    # Changes a Hash's keys from Strings to Symbols, recursively.
    #     -- sycobuny

    def keys_to_sym!(hash)
        to_del, to_add, vals = [], [], []

        hash.each do |k, v|
            to_del << k
            to_add << k.to_sym
            vals   << v
        end

        to_del.each { |d| hash.delete(d) }
        to_add.each_with_index { |a, i| hash[a] = vals[i] }
        vals.each { |v| keys_to_sym!(v) if v.is_a?(Hash) }

        hash
    end

    def app_exit
        @logger.close if @logger
        File.delete('var/ircd.pid')
        exit
    end
end

end # module IRC
