module CiCd
  module Builder
    # noinspection RubySuperCallWithoutSuperclassInspection
    module EnvironmentsList
      CLASS = 'CiCd::Builder::EnvironmentsList'
      module Build

        alias_method :super_prepareBuild, :prepareBuild
        # ---------------------------------------------------------------------------------------------------------------
        # noinspection RubyHashKeysTypesInspection
        def prepareBuild()
          @logger.step CLASS+'::'+__method__.to_s
          # self.class.superclass.instance_method(:prepareBuild).bind(self).call()
          super_prepareBuild
          if 0 == @vars[:return_code]
            @vars[:components] = {}
            @vars[:artifacts] = []
            # Now we need to pull the current environments list
            # Get the repo a little earlier than the typical build which uses it as a write target iso a read source
            getRepoInstance('Artifactory')
            if 0 == @vars[:return_code]
              getLatestEnvironments()
            end
          end

          @vars[:return_code]
        end

        # ---------------------------------------------------------------------------------------------------------------
        def loadEnvironments(filename,version,changed=false)
          require 'hashie'
          @vars[:environments] = {
              file: filename,
              version: version,
              changed: (changed or not File.exists?(filename)),
          }
          data = IO.read(filename) rescue '{}'
          json = begin
            JSON.parse(data)
          rescue
            eval(data)
          end
          IO.write(filename, JSON.pretty_generate(json, {indent: "\t", space: ' '})) # Just to be tidy :)
          @vars[:environments][:data] = Hashie::Mash.new(json)
          @logger.info "#{ENV['ARTIFACTORY_ENVIRONMENTS_MODULE']}-#{version}"
        end

        # ---------------------------------------------------------------------------------------------------------------
        def getLatestEnvironments(oldver=nil)
          version = @repo.latestArtifactoryVersion(ENV['ARTIFACTORY_ENVIRONMENTS_MODULE'], ENV['ARTIFACTORY_RELEASE_REPO'])
          if version
            if version != oldver
              objects = @repo.maybeArtifactoryObject(ENV['ARTIFACTORY_ENVIRONMENTS_MODULE'], version, false, ENV['ARTIFACTORY_RELEASE_REPO'])
              if objects and objects.size > 0
                if objects.size > 1
                  @logger.error "Too many versions found for #{ENV['ARTIFACTORY_RELEASE_REPO']}/#{ENV['ARTIFACTORY_ENVIRONMENTS_MODULE']}-#{version} during preparation?"
                  @vars[:return_code] = Errors::ARTIFACT_MULTI_MATCH
                else
                  loadEnvironments(objects[0].download(), version)
                end
              else
                @logger.error "Version not found for #{ENV['ARTIFACTORY_RELEASE_REPO']}/#{ENV['ARTIFACTORY_ENVIRONMENTS_MODULE']}-#{version} during preparation?"
                @vars[:return_code] = Errors::ARTIFACT_NOT_FOUND
              end
            else
              @logger.info "Alread have the latest version (#{oldver})"
            end
          else
            @logger.warn "No version found for #{ENV['ARTIFACTORY_RELEASE_REPO']}/#{ENV['ARTIFACTORY_ENVIRONMENTS_MODULE']} during preparation?"
            # @vars[:return_code] = Errors::ARTIFACT_NOT_FOUND
            loadEnvironments('/tmp/environments.json', '1', true)
          end
          @vars[:return_code]
        end

        alias_method :super_cleanupBuild, :cleanupBuild
        # ---------------------------------------------------------------------------------------------------------------
        def cleanupAfterUpload()
          @logger.step CLASS+'::'+__method__.to_s
          if @vars[:environments] and @vars[:environments][:file]
            FileUtils.rm_rf(File.dirname(@vars[:environments][:file]))
          end
          0
        end

        # ---------------------------------------------------------------------------------------------------------------
        def packageBuild()
          @logger.info CLASS+'::'+__method__.to_s
          if @vars.has_key?(:environments) and not @vars[:environments].empty?
            @vars[:return_code] = 0
            # Now comes the fun part  ... get the list of profiles/credentials and use AWS SDK to discover environments
            # Let's reuse some code we already have and wrap it in a class
            begin
              require_relative 'lib/update_bucket_policy'
              helper = UpdateBucketPolicy.new
              helper.logger = @logger
              helper.options = Hashie::Mash.new(helper.options.to_hash)
              helper.options[:iniglob]  = ENV['AWS_INI_GLOB'] if ENV['AWS_INI_GLOB']
              helper.options[:inifile]  = ENV['AWS_INI_FILE'] if ENV['AWS_INI_FILE']
              helper.options[:profile]  = ENV['AWS_PROFILE']  if ENV['AWS_PROFILE']
              helper.options[:profiles] = ENV['AWS_PROFILES'] if ENV['AWS_PROFILES']
              helper.prepare_accounts
              if helper.accounts.size > 0
                helper_environments = loadCachedEnvironments()
                unless helper_environments.size > 0
                  helper.get_environments()
                  helper_environments = helper.environments
                  saveCachedEnvironments(helper_environments)
                end

                if helper_environments.size > 0
                  getLatestEnvironments(@vars[:environments][:version])
                  if 0 == @vars[:return_code]
                    environments = Hashie::Mash.new(@vars[:environments][:data])
                    exclude_regex = ENV['ENVS_EXCLUDE_REGEX'] || '-repo'
                    helper_environments.select{|e,_| e !~ /#{exclude_regex}/ }.each do |envnam,_|
                      environments[envnam] ||= {}
                    end
                    if environments.size != @vars[:environments][:data].size
                      IO.write(@vars[:environments][:file], JSON.pretty_generate(environments.to_hash, {indent: "\t", space: ' '}))
                      @vars[:environments][:changed] = true
                    end
                  end
                end
              else
                @logger.error 'No AWS accounts found during preparation?'
                @vars[:return_code] = Errors::NO_ACCOUNTS
              end
            rescue => e
              @logger.fatal "#{e.message}\n#{e.backtrace}"
              @vars[:return_code] = Errors::NO_ACCOUNTS
            end
          else
            @logger.error 'No components found during preparation?'
            @vars[:return_code] = Errors::NO_COMPONENTS
          end
          @vars[:return_code]
        end

        protected

        CACHE_FILE = '/tmp/aws_cloudformation_environments_stacks.json'
        # ---------------------------------------------------------------------------------------------------------------
        def loadCachedEnvironments
          hash = {}
          # if File.exists?(CACHE_FILE)
          # end
          begin
            stat = File.stat(CACHE_FILE)
            age  = (Time.now - stat.mtime)
            @logger.info "Environment stacks cache #{CACHE_FILE} age is #{age}s"
            if age < 3600
              hash = JSON.parse(IO.read(CACHE_FILE))
            else
              hash = {}
            end
          rescue
            hash = {}
          end
          hash
        end

        # ---------------------------------------------------------------------------------------------------------------
        def saveCachedEnvironments(environments)
          IO.write(CACHE_FILE,JSON.pretty_generate(environments,{ indent: "\t", space: ' '}))
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
          opts = @options.dup
          @options = Hash.new()
          opts.each do |k,v|
            @options[k.to_sym] = v
          end
        end

      end
    end
  end
end
