require 'thor'
require 'awesome_print'
require 'inifile'

module Amplify
  module AWS
    LOG_LEVELS = [:trace, :debug, :info, :step, :warn, :error, :fatal, :todo]

    class CredentialsHash < Hash
      def initialize
        super()
      end
    end
    
    class IniFileCredentials < CredentialsHash
      def initialize(inifile)
        super()
        self.[]=(:inifile, inifile)
      end
      def get_options
        {
            :inifile => self.[](:inifile),
            :account => File.basename(self.[](:inifile)),
        }
      end
    end

    class ProfileCredentials < CredentialsHash
      def initialize(profile)
        super()
        self.[]=(:profile, profile)
      end
      def get_options
        {
            :profile => self.[](:profile),
            :account => self.[](:profile),
        }
      end
    end

    module MixIns
      module NoCommands
        require 'dldinternet/mixlib/logging'
        include DLDInternet::Mixlib::Logging

        def validate_options
          @config = @options.dup
          if @config[:log_level]
            log_level = @config[:log_level].to_sym
            raise "Invalid log-level: #{log_level}" unless LOG_LEVELS.include?(log_level)
            @config[:log_level] = log_level
          end
          @config[:log_level] ||= :info
        end

        def parse_options
          validate_options

          colormap = {
              :trace => :blue,
              :debug => :cyan,
              :info  => :green,
              :step  => :green,
              :warn  => :yellow,
              :error => :red,
              :fatal => :red,
              :todo  => :purple,
          }
          unless options[:color]
            LOG_LEVELS.each do |l,_|
              colormap[l] = :clear
            end
          end
          lcs = ::Logging::ColorScheme.new( 'compiler', :levels => colormap)
          scheme = lcs.scheme
          if options[:color]
            scheme['trace'] = "\e[38;5;33m"
            scheme['fatal'] = "\e[38;5;89m"
            scheme['todo']  = "\e[38;5;55m"
          end
          lcs.scheme scheme
          @config[:log_opts] = lambda{|mlll| {
              :pattern      => "%#{mlll}l: %m %g\n",
              :date_pattern => '%Y-%m-%d %H:%M:%S',
              :color_scheme => 'compiler',
              :trace        => (@config[:trace].nil? ? false : @config[:trace]),
              # [2014-06-30 Christo] DO NOT do this ... it needs to be a FixNum!!!!
              # If you want to do ::Logging.init first then fine ... go ahead :)
              # :level        => @config[:log_level],
          }
          }
          @logger = getLogger(@config)

          if @options[:inifile]
            load_credentials_inifile(@options[:inifile], 'global')
          elsif @options[:profile]
            unless File.directory?(File.expand_path('~/.aws'))
              msg = 'Cannot load profile. ~/.aws does not exist!?'
              @logger.error msg
              raise msg
            end
            unless File.exists?(File.expand_path('~/.aws/config'))
              msg = 'Cannot load profile. ~/.aws/config does not exist!?'
              @logger.error msg
              raise msg
            end
            unless File.exists?(File.expand_path('~/.aws/credentials'))
              msg = 'Cannot load profile. ~/.aws/credentials does not exist!?'
              @logger.error msg
              raise msg
            end
            @logger.debug "Profile: #{@options[:profile]}"
            load_credentials_profile(@options[:profile],  {
                                                            'output'                => 'AWS_DEFAULT_OUTPUT',
                                                            'region'                => 'AWS_DEFAULT_REGION',
                                                            'aws_access_key_id'     => 'AWS_ACCESS_KEY_ID',
                                                            'aws_secret_access_key' => 'AWS_SECRET_ACCESS_KEY',
                                                          })
          end

          if options[:debug]
            @logger.info "Options:\n#{options.ai}"
          end

        end

        def expand_options()
          def _expand(opts,k,v,regex,rerun)
            matches = v.match(regex)
            if matches
              var = matches[1]
              if opts[var]
                opts[k]=v.gsub(/\%\(#{var}\)/,opts[var]).gsub(/\%#{var}/,opts[var])
              else
                rerun[var] = 1
              end
            end
          end

          pending = nil
          rerun   = {}
          begin
            pending = rerun
            rerun   = {}
            @options.to_hash.each{|k,v|
              if v.to_s.match(/\%/)
                _expand(@options,k,v,%r'[^\\]\%\((\w+)\)', rerun)
                _expand(@options,k,v,%r'[^\\]\%(\w+)',     rerun)
              end
            }
            # Should break out the first time that we make no progress!
          end while pending != rerun
        end

        def load_credentials_profile(profile, map=nil)
          begin
            if @saved_env and @saved_env.size > 0
              @saved_env.each do |k,v|
                ENV[k] = v
              end
              ENV.to_hash.each do |k,v|
                unless @saved_env.has_key?(k)
                  ENV.delete(k)
                end
              end
            else
              @saved_env = ENV.to_hash.dup
            end
            ini = load_inifile('~/.aws/config')
            ini['default'].each{ |key,value|
              k = if map[key.to_s]
                    map[key.to_s]
                  else
                    key.to_s
                  end
              ENV[k]=value
            }
            ini["profile #{profile}"].each{ |key,value|
              k = if map[key.to_s]
                    map[key.to_s]
                  else
                    key.to_s
                  end
              ENV[k]=value
            }
             ini = load_inifile('~/.aws/credentials')
            unless ini.sections.include?(profile)
              logger.error "No credentials found for profile #{profile}"
              exit 11
            end
            ini[profile].each{ |key,value|
              k = if map[key.to_s]
                    map[key.to_s]
                  else
                    key.to_s
                  end
              ENV[k]=value
            }
            expand_options()
          rescue ::IniFile::Error => e
            # noop
          rescue SystemExit => e
            raise e
          rescue ::Exception => e
            @logger.error "#{e.class.name} #{e.message}"
            raise e
          end
        end

        def load_inifile(inifile)
          inifile = File.expand_path(inifile)
          unless File.exist?(inifile)
            raise "#{inifile} not found!"
          end
          begin
            ini = ::IniFile.load(inifile)
          rescue ::Exception => e
            @logger.error "#{e.class.name} #{e.message}"
            raise e
          end
        end

        def load_credentials_inifile(inifile, section='global', map=nil)
          begin
            ini = load_inifile(inifile)
            ini[section].each{ |key,value|
              #@options[key.to_s]=value
              @logger.debug "#{key} '#{value}'"
              ENV[key.to_s]=value.to_s
            }
            expand_options()
          rescue ::IniFile::Error => e
            # noop
          rescue ::Exception => e
            @logger.error "#{e.class.name} #{e.message}"
            raise e
          end
        end

        def check_missing_options(method,optionset)
          parse_options
          missing = []
          optionset.each do |req|
            case req.class.name
              when /String|Symbol/
                missing << req unless @options[req]
              when /Array/
                flag = false
                req.each do |o|
                  if @options[o]
                    flag = true
                    break
                  end
                end
                missing << req.join('|') unless flag
              else
                logger.fatal "Internal: #{method}: Unsupported missing option type: #{req.class}"
                exit 99
            end
          end

          if missing.size > 0
            logger.error "#{method}: Missing required options: #{missing.join(', ')}"
            exit 1
          end
        end

        def print_error(err)

          logger.error err.to_s

        end

        def prepare_accounts
          @accounts = []
          if @options[:iniglob]
            iniglob = File.expand_path(@options[:iniglob])
            Dir.glob( iniglob) {| filename |
              @accounts << IniFileCredentials.new(filename)
            }
          elsif @options[:inifile]
            @accounts << IniFileCredentials.new(@options[:inifile]) unless (@options[:inifile].nil? or @options[:inifile].empty?)
          end

          if @options[:profile]
            if @options[:profiles]
              @options[:profiles] << @options[:profile]
            else
              @options[:profiles] = [@options[:profile]]
            end
          end
          if @options[:profiles]
            @options[:profiles].each {| profile |
              @accounts << ProfileCredentials.new(profile)
            }
          end
          unless @accounts.size > 0
            parse_options
            logger.fatal 'No options allow for account identification'
          end
          # Make the options mutable
          unless @options.is_a?(Hash) or @options.is_a?(Hashie::Mash)
            @options = Hashie::Mash.new(@options.to_hash)
          end
        end
      end
    end
  end
end
