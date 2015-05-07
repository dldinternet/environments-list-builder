#!/usr/bin/env ruby

require 'thor'
require 'awesome_print'
require 'inifile'
require 'rubygems'
require 'aws-sdk-core'
require 'json'

# =====================================================================================================================
# A little include path tom-foolery ...
path = File.dirname(__FILE__)
# Borrowing from "whiches" gem ...
cmd  = File.basename(__FILE__, '.rb')
exes = []
exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
ENV['PATH'].split(File::PATH_SEPARATOR).each do |pth|
  exts.each { |ext|
    exe = File.join(pth, "#{cmd}#{ext}")
    exes << exe if File.executable? exe
  }
end
if exes.size > 0
  path = File.dirname(exes[0])
end

# add_path = File.expand_path(File.join(path, '../../lib'))
# $:.unshift(add_path)
# add_path = File.expand_path(File.join(path, 'lib'))
add_path = path
$:.unshift(add_path)

# =====================================================================================================================
class UpdateBucketPolicy < Thor
  KNOWN = %w(38.117.159.162/32 70.151.98.131/32 )
  class_option :verbose,      :type => :boolean
  class_option :debug,        :type => :boolean
  class_option :log_level,    :type => :string, :banner => 'Log level ([:trace, :debug, :info, :step, :warn, :error, :fatal, :todo])', :default => :step
  class_option :bucket,       :type => :string, :default => 'wgen-sto-artifacts'
  class_option :bucketini,    :type => :string
  class_option :bucketprofile,:type => :string
  class_option :basepolicy,   :type => :string
  class_option :policy,       :type => :string
  class_option :iniglob,      :type => :string
  class_option :inifile,      :type => :string
  class_option :profiles,     :type => :array
  class_option :color,        :type => :boolean, :default => false
  class_option :yes,          :type => :boolean
  attr_reader   :accounts, :environments, :stacks, :clients
  attr_accessor :logger

  no_commands do

    require 'mixins/no_commands'
    include Amplify::AWS::MixIns::NoCommands

    def get_environments(strict=false)
      logger.step 'Get environments ...'

      @environments = {}
      @nats         = {}
      @accounts.each do |acc|
        @options.merge!(acc.get_options())
        parse_options
        get_environments_for_account(strict)
      end
      logger.info "Environments:\n"+@environments.ai
      logger.info "NATs:\n"+@nats.ai

    end

    def get_environments_for_account(strict=false)
      logger.step "Get environments for #{@options[:account]} ..."

      config = @options

      # noinspection RubyArgCount
      cfn = Aws::CloudFormation::Client.new(retry_limit: 10)

      stacks = []
      resp = cfn.list_stacks()

      stacks << resp[:stack_summaries]
      while resp[:next_token]
        resp = cfn.list_stacks(next_token: resp[:next_token])
        logger.debug resp.size
        stacks << resp[:stack_summaries]
      end
      stacks.flatten!
      stacks = stacks.select{ |stack| stack[:stack_status].match(%r'^(UPDATE|CREATE).*?_COMPLETE$')}
      logger.debug stacks.ai

      stacks.each do |stack|
        env = nil
        resp = cfn.describe_stacks(stack_name: stack[:stack_id])
        stck = resp[:stacks].shift
        tags = stck[:tags]
        tags.each do |tag|
          if tag[:key] == 'EnvironmentName'
            env = tag[:value]
            break
          end
        end
        unless env or strict
          env = stack[:stack_name]
        end
        if env
          @environments[env] ||= []
          @environments[env] << stack[:stack_name]
          @stacks ||= {}
          @stacks[env] ||= []
          @stacks[env] << stack
          @clients ||= {}
          @clients[env] ||= cfn

          # @resources ||= {}
          # @resources[env] ||= []
          resources = []
          resp = cfn.describe_stack_resources(stack_name: stack[:stack_id], logical_resource_id: 'NATIPAddress')
          resources << resp[:stack_resources]
          resp = cfn.describe_stack_resources(stack_name: stack[:stack_id], logical_resource_id: 'BastionIPAddress')
          resources << resp[:stack_resources]
          resources.flatten!
          logger.debug resources.ai

          _nats = resources.map{ |r|
            r.to_h[:physical_resource_id]
          }

          @nats[env] = @nats[env] ? [ @nats[env], _nats ].flatten : _nats
        end
      end

    end

    def get_eips_for_account
      logger.step "Get EIPs for #{@options[:inifile]} ..."

      # noinspection RubyArgCount
      ec2 = Aws::EC2::Client.new(retry_limit: 10)

      resp = ec2.describe_addresses()

      @eips << resp[:addresses].map{ |a| a[:public_ip] }
      @eips.flatten!
      logger.debug @eips.ai

    end

    def get_eips
      logger.step 'Get EIPs ...'

      @eips         = []
      @accounts.each do |acc|
        @options.merge!(acc.get_options())
        parse_options
        get_eips_for_account
      end
      @eips.uniq!
      logger.info "EIPs:\n"+@eips.sort_by { |ip| ip.split(%r'[\./]').map{ |octet| octet.to_i} }.ai

    end

    def read_bucket_policy

      parse_bucket_options(__method__, [ :policy, [:bucketini, :bucketprofile], :bucket ])

      logger.step "Read the current policy for #{@options[:bucket]} ..."

      # noinspection RubyArgCount
      s3 = Aws::S3::Client.new()

      resp = s3.get_bucket_policy(bucket: options[:bucket])
      logger.debug resp.size
      @policies = []
      resp.each do |item|
        json = item.policy.read
        @policies << JSON.load(json)

        logger.debug JSON.pretty_generate(@policies[-1], { indent: "\t", space: ' '})
      end

      logger.debug @policies.ai

      json = ''
      @policies.each do |pol|
        json += JSON.pretty_generate(pol, { indent: "\t", space: ' '})
      end
      IO.write("#{options[:policy]}", json)

    end

    def inspect_bucket_policy

      parse_bucket_options(__method__, [ :policy, [:bucketini, :bucketprofile], :bucket ])

      logger.step "Inspect the policy for #{@options[:bucket]} ..."

      config = @options.dup
      tempfile =
      @options[:policy] = Tempfile.new('policy').path+'.json'
      read_bucket_policy()
      @options = config

      get_eips()

      get_environments()

      ips = [ @nats.values, @eips ].flatten.map{ |ip| "#{ip}/32"}
      ips = [ ips, KNOWN ].flatten.uniq.select{ |ip| not ip.nil? }
      ips = ips.sort_by { |ip| ip.split(%r'[\./]').map{ |octet| octet.to_i} }.uniq
      logger.info "Valid IPs: \n"+ips.ai

      json = ''
      @policies.each do |pol|
        unknown = 0
        missing = 0
        unadded = 0
        if pol['Statement']
          pol['Statement'].each do |smt|
            logger.debug smt.ai
            if smt['Condition'] and smt['Condition']['IpAddress'] and smt['Condition']['IpAddress']['aws:SourceIp']
              smt['Condition']['IpAddress']['aws:SourceIp'].sort_by { |ip| ip.split(%r'[\./]').map{ |octet| octet.to_i} }.each do |entry|
                unless ips.include?(entry)
                  logger.warn "#{entry} unknown"
                  unknown += 1
                end
              end
              ips.each do |entry|
                unless smt['Condition']['IpAddress']['aws:SourceIp'].include?(entry)
                  logger.info "#{entry} missing"
                  missing += 1
                  smt['Condition']['IpAddress']['aws:SourceIp'] << entry
                end
              end
              if missing > 0
                ips.each do |entry|
                  unless smt['Condition']['IpAddress']['aws:SourceIp'].include?(entry)
                    logger.warn "#{entry} missing"
                    unadded += 1
                  end
                end
              end
              smt['Condition']['IpAddress']['aws:SourceIp'] = smt['Condition']['IpAddress']['aws:SourceIp'].sort_by { |ip| ip.split(%r'[\./]').map{ |octet| octet.to_i} }
            end
          end
        else
          logger.warn "Policy has no Statement: #{pol.ai}"
        end
        if missing+unknown > 0
          logger.warn "Policy needs to be updated for #{unknown} unknown IPs, #{missing} missing and #{unadded} IPs which failed to add"
        end
        # require 'date_time'
        logger.debug JSON.pretty_generate(pol, { indent: "\t", space: ' '})
        pol['Id'] = "Policy-#{DateTime.now.strftime('%Y%m%dT%H%M%S')}"
        json += JSON.pretty_generate(pol, { indent: "\t", space: ' '})
      end
      IO.write(options[:policy], json)

    end

    def update_bucket_policy

      parse_bucket_options(__method__, [ :policy, [:bucketini, :bucketprofile], :bucket ])

      logger.step "Update the current policy for #{@options[:bucket]} ..."

      inspect_bucket_policy

      write_bucket_policy

    end

    def write_bucket_policy

      parse_bucket_options(__method__, [ :policy, [:bucketini, :bucketprofile], :bucket ])

      logger.step "Write the new policy for #{@options[:bucket]} ..."

      @options[:inifile] = @options[:bucketini]
      parse_options
      @logger.info options.ai

      json = IO.read(options[:policy])

      # noinspection RubyArgCount
      s3 = Aws::S3::Client.new()

      resp = s3.put_bucket_policy(
                                    bucket: options[:bucket],
                                    policy: json
                                  )
      logger.debug resp.ai
      if resp.error
        logger.error resp.error
      end
    end

    def parse_bucket_options(method,optionset)
      check_missing_options(method, optionset)

      if @options[:bucketini]
        @options[:inifile] = @options[:bucketini]
      else
        @options[:profile] = @options[:bucketprofile]
      end
      parse_options
      @logger.info options.ai
    end
  end

  def initialize(args = [], local_options = {}, config = {})
    super(args,local_options,config)
  end

  desc 'read', 'read the policy for BUCKET'
  def read()
    prepare_accounts

    read_bucket_policy

    n = 1
    @policies.each do |pol|
      logger.step "#{n+=1}\n"+JSON.pretty_generate(pol, { indent: "\t", space: ' '})
    end

    0
  end

  desc 'inspect', 'inspect the policy for BUCKET'
  def inspect()
    prepare_accounts()

    inspect_bucket_policy()

    @policies.each do |pol|
      logger.debug JSON.pretty_generate(pol, { indent: "\t", space: ' '})
    end
    0
  end

  desc 'update', 'update the policy for BUCKET'
  def update()
    prepare_accounts()

    update_bucket_policy()

    0
  end

  desc 'write', 'write the new POLICY to BUCKET'
  def write()
    prepare_accounts
    @options[:inifile] = @options[:bucketini]
    parse_options
    @logger.info options.ai

    write_bucket_policy

    0
  end

end

# =====================================================================================================================
# UpdateBucketPolicy.start(ARGV)


__END__
					"aws:SourceIp": [
						"54.84.38.255/32",
						"54.86.79.230/32",
						"54.84.206.23/32",
						"54.172.63.6/32",
						"54.86.33.222/32",
						"38.117.159.162/32",
						"70.151.98.131/32",
						"54.208.252.192/32",
						"54.86.6.21/32",
						"54.86.156.100/32",
						"54.209.155.115/32",
						"107.23.90.79/32",
						"54.172.109.59/32",
						"54.209.93.210/32",
						"54.88.205.140/32",
						"54.209.196.100/32",
						"54.84.6.106/32",
						"54.165.122.109/32",
						"107.21.36.141/32",
						"54.86.150.196/32",
						"54.209.17.121/32",
						"54.84.31.228/32",
						"54.88.2.227/32",
						"54.85.80.166/32",
						"54.86.31.209/32",
						"50.19.114.108/32",
						"54.85.159.92/32",
						"54.85.129.109/32",
						"54.165.86.129/32",
						"54.165.114.103/32",
						"54.172.8.125/32",
						"54.86.144.175/32",
						"107.23.57.237/32",
						"54.165.231.248/32",
						"54.165.228.106/32"
					]

{
	"Version": "2008-10-17",
	"Id": "Policy13947375644752",
	"Statement": [
		{
			"Sid": "Stmt13947375624982",
			"Effect": "Allow",
			"Principal": {
				"AWS": "*"
			},
			"Action": "s3:*",
			"Resource": "arn:aws:s3:::wgen-sto-artifacts/*",
			"Condition": {
				"IpAddress": {
					"aws:SourceIp": [
						"54.86.79.230/32",
						"54.84.206.23/32",
						"54.86.33.222/32",
						"38.117.159.162/32",
						"70.151.98.131/32",
						"54.209.155.115/32",
						"107.23.90.79/32",
						"54.209.93.210/32",
						"54.88.205.140/32",
						"54.84.6.106/32",
						"107.21.36.141/32",
						"54.86.150.196/32",
						"54.209.17.121/32",
						"54.84.31.228/32",
						"54.86.31.209/32",
						"50.19.114.108/32",
						"54.85.129.109/32",
						"54.165.86.129/32",
						"54.165.114.103/32",
						"54.172.8.125/32",
						"54.86.144.175/32",
						"107.23.57.237/32",
						"54.165.231.248/32",
						"54.165.228.106/32"
					]
				}
			}
		},
		{
			"Sid": "2",
			"Effect": "Allow",
			"Principal": {
				"AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity EXU2IEU8NKUSP"
			},
			"Action": "s3:GetObject",
			"Resource": "arn:aws:s3:::wgen-sto-artifacts/*"
		}
	]
}