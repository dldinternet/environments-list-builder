require 'aws-sdk-core'
require 'aws-sdk-resources'
require 'uri'

# ---------------------------------------------------------------------------------------------------------------
def getS3()
  region = ENV['AWS_REGION'] || ::Aws.config[:region] || 'us-east-1'
  unless @s3
    # noinspection RubyArgCount
    @s3 = ::Aws::S3::Client.new(region: region)
  end
  unless @s3 and ((@s3.config.access_key_id and @s3.config.secret_access_key) or @s3.config.credentials)
    @logger.warn "Unable to find AWS credentials in standard locations:
ENV['AWS_ACCESS_KEY'] and ENV['AWS_SECRET_ACCESS_KEY']
Aws.config[:credentials]
Shared credentials file, ~/.aws/credentials
EC2 Instance profile
"
    if ENV['AWS_PROFILE']
      @logger.info "Trying profile '#{ENV['AWS_PROFILE']}' explicitly"
      creds = Aws::SharedCredentials.new( path: File.expand_path('~/.aws/credentials'), profile: ENV['AWS_PROFILE'] )
      if creds.loadable?
        # noinspection RubyArgCount
        @s3 = ::Aws::S3::Client.new(region: region, credentials: creds)
      end
    else
      @logger.warn 'No AWS_PROFILE defined'
    end
  end
  unless @s3 and ((@s3.config.access_key_id and @s3.config.secret_access_key) or @s3.config.credentials)
    raise 'Unable to find AWS credentials!'
  end
  @s3
end

# ---------------------------------------------------------------------------------------------------------------
def getBucket(name = nil)
  @s3 = getS3()
  begin
    ::Aws::S3::Bucket.new(name: name || ENV['AWS_S3_BUCKET'], client: @s3)
  rescue Aws::S3::Errors::NotFound
    @vars[:return_code] = Errors::BUCKET
    nil
  rescue Exception => e
    @logger.error "S3 Bucket resource API error: #{e.class.name} #{e.message}"
    raise e
  end
end

# ---------------------------------------------------------------------------------------------------------------
def getObjects(artifact, path)
  parts = URI(path).path.gsub(%r'^#{File::SEPARATOR}', '').split(File::SEPARATOR)
  name = parts.shift
  bucket = getBucket(name)
  key = File.join(parts, '')
  @logger.info "S3://#{name}:#{key} URL: #{path} #{artifact}"
  objects = []
  bucket.objects(prefix: key).each do |object|
    if artifact.empty? or (not artifact.empty? and object.key =~ %r'#{key}#{artifact}')
      objects << object
    end
  end
  @logger.debug "S3://#{name}:#{key} has #{objects.size} objects"
  return key, name, objects
end

# ---------------------------------------------------------------------------------------------------------------
def calcLocalETag(etag, local, size = nil)
  if size == nil
    stat = File.stat(local)
    size = stat.size
  end
  @logger.debug "Calculate etag to match #{etag}"
  match = etag.match(%r'-(\d+)$')
  check = if match
            require 's3etag'
            parts = match[1].to_i
            chunk = size.to_f / parts.to_f
            mbs = (chunk.to_f / 1024 /1024 + 0.5).to_i
            part_size = mbs * 1024 * 1024
            chkit = S3Etag.calc(file: local, threshold: part_size, min_part_size: part_size, max_parts: parts)
            @logger.debug "S3Etag Calculated #{chkit} : (#{size} / #{part_size}) <= #{parts}"
            chunks = size / part_size
            while chkit != etag and chunks <= parts and chunks > 0 and (size > part_size)
              # Go one larger if a modulus remains and we have the right number of parts
              mbs += 1
              part_size = mbs * 1024 * 1024
              chunks = size.to_f / part_size
              chkit = S3Etag.calc(file: local, threshold: part_size, min_part_size: part_size, max_parts: parts)
              @logger.debug "S3Etag Calculated #{chkit} : (#{size} / #{part_size}) <= #{parts}"
            end
            #raise "Unable to match etag #{etag}!" if chkit != etag
            chkit
          else
            Digest::MD5.file(local).hexdigest
          end
end

# ---------------------------------------------------------------------------------------------------------------
def shouldDownload?(etag, local, object)
  if File.exists?(local)
    @logger.debug "\t\tchecking etag on #{local}"
    stat = File.stat(local)
    check = calcLocalETag(etag, local, stat.size)
    if etag != check or object.size != stat.size or object.last_modified > stat.mtime
      @logger.debug "\t\t#{etag} != \"#{check}\" #{object.size} != #{stat.size} #{object.last_modified} > #{stat.mtime}"
      true
    else
      @logger.debug "\t\tmatched #{etag}"
      false
    end
  else
    true
  end
end

# ---------------------------------------------------------------------------------------------------------------
def doDownload(etag, local, object)
  @logger.info "\t\tdownload #{object.size} bytes"
  response = object.get(:response_target => local)
  File.utime(response.last_modified, response.last_modified, local)
  @logger.info "\t\tdone"
  check = calcLocalETag(etag, local)
  if check.eql?(etag)
    false
  else
    @logger.info "\tETag different: #{etag} != #{check}"
    true
  end
end


class FakeLogger
  def initialize

  end

  def method_missing(*args)
    puts "#{args[0]}: #{args[1..-1].join(' ')}"
  end
end

@logger = FakeLogger.new()
artifact, path = ['', 'https://s3.amazonaws.com/wgen-sto-artifacts/release/com/amplify/learning/enrollment/1.3.0-265']
local_dir = File.join('/tmp', 'enrollment', '')
Dir.mkdir(local_dir, 0700) unless File.directory?(local_dir)
artifacts = []

key, name, objects = getObjects(artifact, path)
# 1 or more objects on the key/ path
if objects.size > 0
  objects.each do |object|
    @logger.info "\tchecking #{object.key}"
    local = File.join(local_dir, File.basename(object.key))
    etag = object.etag.gsub(%r/['"]/, '')
    download = shouldDownload?(etag, local, object)
    if download
      changed = doDownload(etag, local, object)
    else
      @logger.info "\t\tunchanged"
    end
    artifacts << local
  end
else
  @logger.fatal "Artifact not found: s3://#{name}/#{key}#{artifact}"
end
