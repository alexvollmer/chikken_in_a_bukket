require 'rubygems'
require 'mosquito'
require File.dirname(__FILE__) + "/../lib/chikken_in_a_bukket"

class ObjectStub
  attr_reader :key
  
  def initialize(key)
    @key = key
  end
  
  def size
    100
  end
end

class BucketStub
  attr_reader :name, :objects
  
  def initialize(name)
    @name = name
    @objects = {}
  end
  
  def add_object(key)
    @objects[key] = ObjectStub.new(key)
  end
    
  def to_s
    @name
  end
  
end

class ConnectionStub
  
  def initialize
    @buckets = {}
  end
  
  def add_bucket(name)
    bucket = BucketStub.new(name)
    if block_given?
      yield bucket
    end
    @buckets[name] = bucket
  end
  
  def bucket_names
    @buckets.keys
  end
  
  def create_bucket(name)
    if @buckets.keys.member?(name)
      raise S33r::S3Exception::S3OriginatedException.new('BucketAlreadyExists')
    else
      bucket = BucketStub.new(name)
      @buckets[name] = bucket
      bucket
    end
  end
  
  def list_bucket(bucket, options={})
    listing = @buckets[bucket].objects
    class << listing
      def is_truncated
        false
      end
    end
    listing
  end
end

class ChikkenInaBukket::Config
  
  @@connection = nil
  
  def self.connection
    @@connection
  end
  
  def self.connection=(conn)
    @@connection = conn
  end
  
  def self.configured=(val)
    @@configured = val
  end

end

class TestChikkenInaBukket < Camping::FunctionalTest
  
  def setup
    super
    @connection = ConnectionStub.new
    ChikkenInaBukket::Config.connection = @connection
    
    @connection.add_bucket("bucket1") do |bucket|
      bucket.add_object("key 1")
      bucket.add_object("key 2")
    end
    
    @connection.add_bucket("bucket2") do |bucket|
      bucket.add_object("key 3")
      bucket.add_object("key 4")
    end
  end
  
  def test_get_slash_no_config_file
    ChikkenInaBukket::Config.configured = false
    
    get '/'
    assert_response :redirect
    assert_redirected_to "/configuration"
  end
  
  def test_get_slash
    get '/'
    assert_response :success
    assert_match_body /bucket1/
    assert_match_body /bucket2/
  end
  
  def test_create_bucket
    post '/', :bucket => "bucket3"
    assert_response :redirect
    assert_redirected_to '/buckets/bucket3'
  end
  
  def test_create_bucket_already_exists
    post '/', :bucket => "bucket1"
    assert_response :success
    assert_match_body /Sorry, the bucket bucket1 already exists. Try another name./
  end
  
  def test_create_bucket_unknown_error
    class << @connection
      def create_bucket(bucket)
        raise S33r::S3Exception::S3OriginatedException.new('SomeOtherError', 'your error here')
      end
    end
    post '/', :bucket => "bucket3"
    assert_response :success
    assert_match_body /Error your error here/
  end
  
  def test_get_buckets
    get '/buckets/bucket1'
    assert_response :success
    assert_match_body /key 1/
    assert_match_body /key 2/
  end
end