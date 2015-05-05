require 'json'

module CiCd
	module Builder
    # noinspection RubySuperCallWithoutSuperclassInspection
    module EnvironmentsList
      module Repo
        require 'cicd/builder/mixlib/repo/base'
        require 'cicd/builder/mixlib/repo/S3'
        # noinspection RubyResolve
        if ENV.has_key?('REPO_TYPE') and (not ENV['REPO_TYPE'].capitalize.eql?('S3'))
          require "cicd/builder/environments-list/mixlib/repo/#{ENV['REPO_TYPE'].downcase}"
        end

        # ---------------------------------------------------------------------------------------------------------------
        def getRepoClass(type = nil)
          @logger.step CLASS+'::'+__method__.to_s
          if type.nil?
            type ||= 'S3'
            if ENV.has_key?('REPO_TYPE')
              type = ENV['REPO_TYPE']
            end
          end

          @logger.info "#{type} repo interface"
          clazz = begin
                    Object.const_get("#{self.class.name.gsub(%r'::\w+$', '')}::Repo::#{type}")
                  rescue NameError => e
                    begin
                      # Object.const_get("#{self.class.name.gsub(%r'::\w+$', '')}::Repo::#{type}")
                      Object.const_get("CiCd::Builder::Manifest::Repo::#{type}")
                    rescue NameError #=> e
                      Object.const_get("CiCd::Builder::Repo::#{type}")
                    end
                  end

          if block_given?
            if clazz.is_a?(Class) and not clazz.nil?
              yield
            end
          end

          clazz
        end

      end
    end
  end
end
