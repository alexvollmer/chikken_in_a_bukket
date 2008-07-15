require 'pp'
require 'rubygems'
require 'base64'
require 'camping'
require 's33r'
require 'action_pack'
require 'action_view/helpers/number_helper'

Camping.goes :ChikkenInaBukket

module ChikkenInaBukket

  VERSION = '0.9.1'

  class Config
    @@access_key = nil
    @@secret_key = nil
    @@conn = nil
    @@configured = false
    
    def self.initialize
      begin
        @@config = open("#{ENV['HOME']}/.chikken_in_a_bukket.yml") { |f| YAML.load(f) }

        @@access_key = @@config["access_key_id"]
        @@secret_key = @@config["secret_access_key"]

        @@conn = S33r::Client.new(:access => @@access_key, 
                                  :secret => @@secret_key,
                                  :use_ssl => @@config["use_ssl"])
        @@configured = true
      rescue Errno::ENOENT => e
        @@configured = false
      end
    end
    
    def self.configured?
      @@configured
    end
    
    def self.connection
      @@conn
    end
    
    def self.access_key
      @@access_key
    end
    
    def self.secret_key
      @@secret_key
    end
  end
  
  Config.initialize
end

module ChikkenInaBukket::Controllers
  class BackgroundImage < R '/background.gif'
    def get
      @headers['Content-Type'] = 'image/gif'
      @headers['Content-Length'] = ChikkenInaBukket::BACKGROUND.length
      Base64.decode64(ChikkenInaBukket::BACKGROUND)
    end
  end
  
  class BucketImage < R '/bucket.png'
    def get
      @headers['Content-Type'] = 'image/png'
      @headers['Content-Length'] = ChikkenInaBukket::BUCKET.length
      Base64.decode64(ChikkenInaBukket::BUCKET)
    end
  end
  
  class Stylesheet < R '/style.css'
    def get
      @headers['Content-Type'] = 'text/css'
      <<-CSS
      body {
        font: "Lucida Grande", "Trebuchet MS", Verdana, sans-serif;
        font-size: 80%;
      	background-color: white;
        background-image: url('/background.gif');
        background-position: top;
      	background-repeat: repeat-x;
      	padding: 10px;
      }

      .separator {
        padding-left: 5px;
        padding-right: 5px;
      }

      a, a:visited {
        color: #666;
      }

      div.bucket {
        position: absolute;
        right: 10px;
        bottom: 10px;
      }
      
      fieldset {
        width: 50%;
        padding: 10px;
      }
      
      input {
        margin-right: 10px;
      }
      
      input {
        background-color: #eee;
      }
      
      label {
        display: block;
      }
      
      span.delete {
        padding: 10px;
        font-size: 80%;
        font-weight: bold;
      }
      
      .flash {
        color: #af2219;
        font-weight: bold;
      }
      CSS
    end
  end
  
  class Index < R '/'
    def get
      unless Config.configured?
        return redirect(Configuration)
      else
        @buckets = Config.connection.bucket_names
        render :index
      end
    end
    
    def post
      begin
        @bucket = Config.connection.create_bucket(@input[:bucket])
        @objs = []
        return redirect(Buckets, @bucket.name)
      rescue S33r::S3Exception::S3OriginatedException => e
        @buckets = Config.connection.bucket_names
        if e.s3_code == 'BucketAlreadyExists'
          @flash = "Sorry, the bucket #{@input[:bucket]} already exists. Try another name."
        else
          @flash = "Error #{e.s3_message}"
        end
        render :index
      end
    end
  end
  
   class Buckets < R '/buckets/(.+)'
    include ActionView::Helpers::NumberHelper
    
    MAX_KEYS = 15

    def get(bucket)
      bucket.sub!(/\/$/, '')
      options = {}
      
      case @input[:action]
      when "next"
        options[:marker] = @input[:last_key]
        options[:max_keys] = MAX_KEYS + 1
      when "previous"
        unless @input[:action] == "first"
          options[:marker] = @input[:first_key]
          options[:max_keys] = MAX_KEYS + 1
        end
      else
        options[:max_keys] = MAX_KEYS
      end

      listing = Config.connection.list_bucket(bucket, options)
      @objs = listing.entries.map { |x| x[1] }
      @objs.sort! { |a,b| a.key <=> b.key }
      @bucket = bucket
          
      if @input[:first_key] and @input[:first_key] != @objs.first.key
        if @input[:first_key] == "first"
          @previous_url = navigation_url(bucket)
        else
          @previous_url = 
            navigation_url(bucket, 
                           :first_key => @input[:first_key], 
                           :last_key => @objs.last.key, 
                           :action => "previous")
        end
      end
      
      if listing.is_truncated
        @next_url = 
          navigation_url(bucket,
                         :first_key => (@input[:action] ? @objs.first.key : "first"), 
                         :last_key => @objs.last.key, 
                         :action => "next")
      end
      
      render :bucket
    end
    
    private
      def navigation_url(bucket, options={})
        url = "#{R(Buckets, bucket)}/"
        query = options.keys.map  { |key| "#{key}=#{CGI.escape(options[key])}" }.join("&")
        url <<"?#{query}" unless query.empty?
        url
      end
  end
  
  class DeleteBucket < R '/delete_bucket/(.+)'
    def get(bucket)
      Config.connection.delete_bucket(bucket)
      return redirect(Index)
    end
  end
  
  class Delete < R '/delete/(.+?)/(.+)'
    def get(bucket, key)
      @bucket = Config.connection.get_bucket(bucket)
      @bucket.delete(key)
      return redirect(Buckets, bucket)
    end
  end
  
  class Details < R '/details/(.+?)/(.+)'
    include ActionView::Helpers::NumberHelper

    def get(bucket, key)
      @bucket = Config.connection.get_bucket(bucket)
      @obj = @bucket.object(key, :lazy => true)
      @url = @bucket.s3_url(:bucket => bucket, 
                            :key => key, 
                            :authenticated => true,
                            :access => ChikkenInaBukket::Config.access_key,
                            :secret => ChikkenInaBukket::Config.secret_key)
      render :detail
    end
  end
  
  class AddFile < R '/add_file/(.+)'
    def get(bucket)
      @bucket = bucket
      render :add_file_form
    end
    
    def post(bucket)
      Config.connection.put(@input.File['tempfile'].path,
                            :key => @input.File['filename'],
                            :bucket => bucket,
                            :content_type => @input.File['type'],
                            :file => true,
                            :render_as_attachment => true)
      redirect R(Buckets, bucket)
    end
  end
  
  class Configuration < R '/configuration'
    def get
      render :configuration
    end
    
    def post
      open(ENV["HOME"] + "/.chikken_in_a_bukket.yml", "w") do |file|
        file << {
          "access_key_id" => @input[:access_key],
          "secret_access_key" => @input[:secret_key]
        }.to_yaml
      end
      Config.initialize
      return redirect(Index)
    end
  end
end

module  ChikkenInaBukket::Views

  def separator
    span "|", :class => "separator"
  end
  
  def config_link
    a "S3 Configuration", :href => R(Configuration)
  end
  
  def delete_bucket_link(bucket, *text)
    a (text.first ? text.first : "Delete"), 
      :href => R(DeleteBucket, bucket), 
      :onclick => "return confirm('Are you sure you want to delete the bucket #{bucket}?');"
  end
  
  def layout
    html do
      head do
        title 'Chikken in a Bukket'
        link :rel => 'stylesheet',
             :type => 'text/css',
             :href => '/style.css',
             :media => 'screen'
      end
      
      body do
        self << yield
        div :class => 'bucket' do
          img :src => R(BucketImage)
        end
      end
    end
  end
  
  def index
    h1 "Welcome to your S3 Storage"
    h2 "Your current buckets are:"
    if @flash
      h3 @flash, :class => 'flash'
    end
    ul do
      @buckets.each do |bucket|
        li do
          a bucket, :href => R(Buckets, bucket)
          span :class => 'delete' do
            delete_bucket_link(bucket, "[Delete]") 
          end
        end
      end
    end
    
    form :action => "/", :method => "post" do
      fieldset do 
        label "Create a new bucket"
        input :type => "text", :name => "bucket", :size => 25, :class => "bucket"
        input :type => "submit", :name => "Submit", :value => "Make it so!"
      end
    end
    
    hr
    config_link
  end
  
  def bucket
    h1 "Files in bucket #{@bucket}"
    h3 "#{@objs.length} objects in this bucket"
    a "All buckets", :href => R(Index)
    separator
    delete_bucket_link(@bucket, "Delete this bucket")
    separator
    config_link
    separator
    a "Upload a file", :href => R(AddFile, @bucket)
    
    ul do
      @objs.each do |f|
        li do
          a "#{f.key} (#{number_to_human_size f.size})", 
            :href => R(Details, @bucket, f.key)
          span :class => 'delete' do
            a "[Delete]",
              :href => R(Delete, @bucket, f.key),
              :onclick => "return confirm('Are you sure you want to delete #{f.key}?');"
          end
        end
      end
    end
    
    if @previous_url
      a "Back", :href => @previous_url
    end
    separator if @previous_url and @next_url
    if @next_url
      a "More", :href => @next_url
    end
  end
  
  def detail
    h1 "Attributes for #{@obj.key}"
    a "All buckets", :href => R(Index) 
    separator
    a "Back to #{@bucket.name}", :href => R(Buckets, @bucket.name)
    separator
    config_link
    
    ul do
      li "Content-Type: #{@obj.content_type}"
      li "E-Tag: #{@obj.etag}"
      li "Last-Modified: #{@obj.last_modified}"
      li "Size: #{number_to_human_size(@obj.size)}"
    end
    a "Download this file", :href => @url
    separator
    a "Delete this file", :href => R(Delete, @bucket.name, @obj.key), :onclick => "return confirm('Are you sure you want to delete this object?')"
  end
  
  def add_file_form
    h1 "Add a new file to #{@bucket}"
    fieldset do
      legend "File to upload"
      form :method => "post", :enctype => "multipart/form-data" do
        input :name => "File", :type => "file", :size => 30
        p { input :type => "submit", :value => "Upload" }
      end
    end
  end
  
  def configuration
    h1 "Your S3 Configuration"
    a "Return to top", :href => R(Index)
    p "You're not letting anyone look at this over your shoulder, are you?"
    form :action => R(Configuration), 
         :method => "post", 
         :onsubmit => "return confirm('Are you sure you want to change these?');" do
           
      label "Access Key:", :for => 'access_key'
      input :value => ChikkenInaBukket::Config.access_key, 
            :name => "access_key", 
            :type => "text",
            :id => "access_key",
            :size => 30
      label "Secret Key", :for => "secret_key"
      input :value => ChikkenInaBukket::Config.secret_key,
            :name => "secret_key",
            :type => "text",
            :id => "secret_key",
            :size => 40
      br
      
      p do
        input :type => "submit", :name => "submit", :value => "Change 'em!"
        input :type => "reset", :name => "reset", :value => "Nah, forget it"
      end
    end
  end
end

module ChikkenInaBukket
  BACKGROUND = <<EOF
R0lGODlhMgAyAOe2AOXl5eXl5ubl5ebl5uXm5eXm5ubm5ebm5ubm5+fm5ufm
5+bn5ubn5+fn5ufn5+fn6Ojn5+jn6Ofo5+fo6Ojo5+jo6Ojo6eno6Ono6ejp
6Ojp6enp6Onp6enp6urp6erp6unq6enq6urq6erq6urq6+vq6uvq6+rr6urr
6+vr6uvr6+vr7Ozr6+zr7Ovs6+vs7Ozs6+zs7Ozs7e3s7O3s7ezt7Ozt7e3t
7O3t7e3t7u7t7e7t7u3u7e3u7u7u7e7u7u7u7+/u7u/u7+7v7u7v7+/v7u/v
7+/v8PDv7/Dv8O/w7+/w8PDw7/Dw8PDw8fHw8PHw8fDx8PDx8fHx8PHx8fHx
8vLx8fLx8vHy8fHy8vLy8fLy8vLy8/Py8vPy8/Lz8vLz8/Pz8vPz8/Pz9PTz
8/Tz9PP08/P09PT08/T09PT09fX09PX09fT19PT19fX19PX19fX19vb19fb1
9vX29fX29vb29fb29vb29/f29vf29/b39vb39/f39vf39/f3+Pj39/j3+Pf4
9/f4+Pj49/j4+Pj4+fn4+Pn4+fj5+Pj5+fn5+Pn5+fn5+vr5+fr5+vn6+fn6
+vr6+fr6+vr6+/v6+vv6+/r7+vr7+/v7+vv7+/v7/Pz7+/z7/Pv8+/v8/Pz8
+/z8/Pz8/f38/P38/fz9/Pz9/f39/P39/f39/v79/f79/v3+/f3+/v7+/f7+
/v7+///+/v/+//7//v7//////v//////////////////////////////////
////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////
/////////////////////ywAAAAAMgAyAAAI/gAFHCggIMCAAgMEEEgIoAAA
AwYGQiywcIABghcfDghAMICAiwECQEwY4IDFAxEPqFzJsqXLly0XwHTZYAED
BwxUNkDAQMGCBTsTMPh5oMGBBAcU4EyAwIGCBA6iLlDQIOdOBgkWIAC6IKpX
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
EOF

  BUCKET = <<EOF
iVBORw0KGgoAAAANSUhEUgAAAHUAAACBCAYAAAD+B/WzAAAABmJLR0QA/wD/
AP+gvaeTAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAB3RJTUUH1wISEiMNnIU2
gQAAIABJREFUeNrsvHmQZdld3/k5d7/vvv1l5ss9s7L23qoXNepFagmBxCJA
SAJJaMxMDA6wzRgPg8MwMzETMGDCJgyOMYEHcGCCxcZmBiGEhAC1tm71JvVS
vVXXnpV75tvXuy9n/sgSpNJVvUiyYAbdiBP35a3KqLrn+77f3+/3Pb9z4JvX
N69vXt+8vnl98/rm9fW4xDen4KZz8WpzI1/j52+C+rdoDr7a+ZB/mwDW/j+k
IOINTOxrPRev8lkcei5eBTz5Vfx//k4x9fUwRnytkyjdzRQi0FJwh9DYhSQG
XYeFI2SXL6NoFhw5iXBW7Bv8m/IQoPIGzzj053/nmHpDMKPh3o8ZxenfehXW
vF4J/MpJTWIaV86xdeU822tXaO3ugEwxVIOcnedLzz6LbTmcvPs+0s6ar9aW
SzcBKrv+OTv0+cvgikP3vzNMFVFjPWs3txj1OkTeCFvXmJutY83Og1QR5SMW
IORo2xeFuZwc7HqRH2JOLzuvAuANWRJvvRJ+8ZFPcfGlZ0n9PqeOLpEEPv1u
j729PWq1OkLRsO0cmVlAry+xfNud3HLfOydvwNTsAIjpgWfyELivR6r/fwGq
kL2t7ON/+J/oNrbY3byGP+yBTHBMgyPL85w6fStXN3ZZWlmhPj2LRAEU8uUy
tlMgzgTO9AyiOF+6SZz7iomUe1fdL332k3zuL/6UyOtydGGG+Zk6SRiwvrbG
uZfPoygqtYlpLCtH1/OhNMHR285w/1vfwfEzdyGK84uHgMwO3dNDYGd/E8D+
TcivSLYuZB/5rV/jmcc/hyUytCyiahuUCjnSJCLt7DLcMshnsHfheezEJec4
XL58Balq1KdnGXsRZ+66C7nz/IBKDaQENwRFsDsKf2p2+dbfkc31rphaKsvG
xf4XP/ERnnrsM2jhiGreIux1qB1bZJj4LE9PMVOucPHKVXb3dinkSxw7doxh
khB2Ntm99DwzEyUA+wBY6YGRXB/KIZAPSrL4RsVY7RvO0MZq9tiffYSzjz5M
XoSULZ3QGxF1fXw/R5qmKI5NNlliZWmZCxcvEbQs6s4yBTWm3WkSm4Jqocje
6ivMhkOs8TTECaPBiDhNyZvmvw6e+4t/jZkiG+f73qWXSIctjs9PUnHmkUlI
t93g6oVX0AQ4ToHJaolWsUASRgRRSnt3i/rCLGk8Iuw38PsNZG/1oqis3H0I
yIMjvn5PD6lh+o0EVvtGyvzlz34y+/1f/WX89gZ3rsySU2OmygU6zR3WVlcJ
x32SJMHRVWxVUC/kkIszhEHAsLFFUYde5HL15bPkiyUWl47SSSOcbpsgTQnD
kDjJ8MMI33WZvXqBTrvJoNclTTxySsqgt0foDkmigFKpQLVaxXEKaKpFuVyk
VC5zbX2bS5cvoGkhuXIRf5BnZ/UCml1AdteeE9XltxwAMQai63fl+ogPvHsK
qN9IYNVvBKDxznb2bWdO/ewXP/0JtHDAhAVBZxdHk9x67AjL83PUKmVqlSqq
ooKiUCoW2bi2ykSljDsaMhz0OH70KAtz06RRiGXqyDQhjSNC3yMJAwxNwdJU
In9Mr91g9fJ5ijmT6ckyupISh2N0JSNn6ZimTr/fA+Q+U+t12p0uQRARRCGF
gk3k97BMlTST7HXaDN2IXKnCr/zG734E0K/Pn3YdSHGozuUmmbt8ndn830pQ
/+olV4zkZ//8j34PLejjtbaQbpfE71Mvl2g39tja3KRUrnL61tuRqsleu4fn
BdSnahQcCyeXI8syQt+HDE58y5vJxh79Xp87br+dl196gS9+8SlM3eDss8/R
7/UYD/uoIqVUsHnppbM0drbwgxFxHFIql7h46RJOIc/UzDRxmmE5eRTNYDh2
OXHqNKVSnjgcEoYea1ubNDp9hGVj5gr8i3/xC//Nv/o3v/mxA8AqB4B9rXLt
tcyOv5XZr/jrDHcjZe0i//Kf/zybl89xamUeWyRYqsTtt8nnLKanp2l1euw2
GiysnOS2M3djF8qksY9BhKGAaVu0Wi1sJ09/MMK2HSan66iaRRhHXLpylVze
4Zmnn8PMOYRhiK6rTE5VsQ2dre0NVFWgawpJElMoFGi0moRhyIlTpwGFSnWK
Xn/I5sYOSytHsTSIvBatTpO9zgA1X2Ny+VbKsyvMnTzD8TvuQc3P/T0gAPwD
9y+P8Losf1maD2bHNyp7vm52o/ZfBczBbsqwxV/82i8hxx2i9hozJRM19hj7
Y+yyQy6XQ6gqzXYXPwwx7AJjP2K70WZWtykWHHKKxbDbIkkzBv0hM3OLmFaO
a9fWsZwcE5N5+sMBk9UaW7s7nDxxgiAM6feHFAoOuqbQ7bTIkhRTNxGKIEkz
+oMhTqFIf7iN6wVEUYZuFiiVyoxqAb7vE5KQN02Wl1dYWDEI0Em1HCQBmdsl
HbSQ463/IPLzP3J9Hm8kwwdZ+OXsODlgVnAI4MMSLf8mmSqSrUuZWilAu8nF
F57jS498iv7aRWYreRQkpqEz6HUYDwcsLcxhGhq6rrPXaGHl8swsLBLFGc1e
D9PKMTVZo6BKZBqiaxqbW1vccsttVCcn2NltsL61yfFjJ7FyDlEU8ZnPfo5c
LsfI8ymXy0BGGkc0m3sIIVF0DSEkYRwRBAGFcgnLzJEvltja3GFycoqTp26h
0+mxu9tgOOgQ+yOOHV/GyBXoDX0U06E4NYvmFJGayUPvff+++qYpSRgTxzGJ
TFAUBVU1UfUczUHwm/PHb//n1xmbHCp5DjP2RhbkG2bt1wRq0m0+o1Wn7gXE
lU/+fvryl55ga/UiizN18qaCGnuoZARBQBAEjAYDTNOkXC7S7/fJMkiyDF3X
EUJFCigUCjiOQxKFGKTkHYt8zqHT65Jlkql6naVjJ3jysSeo1+tUJyYZj8cI
Ved3fud3qNYmuOeee9ja2qJ9XWJN2yLLMoSQCFXBCwN0w2BmZg7dtNjY2EJK
QX1qhl6vT6fTwdBU0jiiXCkShiF+EDE5M8vE9DRDz2e30+HUbXcQpRlhCqlQ
0A0D3bYxDAOpGswsHKE+u8zCiVMIZ3rpUMlz0KjIDoGbfS3Aiq9VagfPP5K+
+MTn+eRH/jP1oslUOcfK/By91h5jzyWKIoI4IgxihKpRqVSQUrLb2COOEpx8
jixJ8X2XarHA4uIi5VIBkaVEvk+708Q2bHL5PL7vUyiVuO9d7+Lq8y/S7/ex
cnn6/T4rx45z5coVLl68iJXL8eyzLxKOoVjUsHI2hmWhGyqKqiJUhSiKkIrK
/Pw8mmrQ6w1oNdtsb++iKArLC4s4joPMEoLAJ8syVFUljANQFcqTNTIpCbKM
WApU26ZQrlGs1sjlHRTDxsxXmZpb4o6778Wcv/3UgRIoOWReHGRu+rVajdpX
C2j75S9lLzz1BR795J/gt3dQ/R7TswvUDIkV9hjsXKMxdPEzUFQdzTCxTQsv
TvG8AKHZGFqGbpoII6NWLTJVLZFFPt3GkKlalfGwy8a1VUqFMsVyiVwuRxyG
jDY3KTo5uq0mvVaTdrvN9uYmDz74ILvbW6ytrdHahaVZjempWTIk1ckJpJR0
ul1M0yYYRwSRx95GA8fJ0+322dncxRtDuaSgYTDsuggBZBkyi3C9Ef2+T6ms
kq8V0QydIAE3ignHEeMwIBr1MOwCimVTmAgYj8eYpolsX70gJo7efgjYw+Cm
1+c3e414+3UFVcjhZrb+7Bd59GP/EVOkTOUMaqeW8bfOk1dTiAJmqrM4Z27n
ym6PSxs7tNsdFDVA1wziON5nmGWRpimT1RJkKSKLScKIQb9Ht9Oi2+kz9jxS
TKbmluh2u0RpRBC7nHv5EseOHSOOJP1ejzAIUBR4/NHP8W3f9g60dzxEt9sj
71SZmJym1+tRnZrC7fU5e/YshmHQaDRwXZeLl69w9dw6zQ4kEmZmoT5dpViy
6PViSDNc30UhpV6vs3LUJIkiIj/AdUekQkEqyn59qChoQlKwdOySw9UrLxGk
ktgfUyoVkIPNl0Rp4Z5DwMaHXClxwJFKrydXB+X4NROo1y2/crAuw+0rfOqj
/4kXnvoCJ5fmIQ5ZmptlslSAJOaZJx9nolxgolzEtIuME4uXz6/SH3SJYx8n
b2EYGv1Be1/KwpCZmRlM08T3Q7IUFEVDRUW3bdoDjyCKURSNcqFIr9smiWKW
5+fJkoj5uTqPP/YIrd0xs3Mm7/u+d7O4NMfFV85hFRzKU9MIxSD2A7IwxkDB
c13GvdG+KZtKirUKj33pKZr9LvXlJQqVMqmQ5OwiaZgR+fuJlZQSVRUEcUS7
06HT77CxNeTk6Tnml4+w125Rn55F0Q2cQh5vPEJXYs5dvMQ9b30nVm2OmVN3
cdtDP/C2Qy7UQVfqoEt10Fe+mRx/daB2GjuyVp9V3ItfyP7wN34FRm3uOLFI
4g5p7+2ShBG1SpW52Vk6zQZxFKBkGWAwDA3W1nZwvTG+P0LTBXlHRyiSiYka
iqKQyoxOu0tvOMIy8xSKFQqFEvlSjcvrWzQ6XdyRS7VUJokiYt/D0nQa2y1E
Bv/gx97PkYVpsiygMj8NwYjt1Uv4Ucg4zbByeWzNIqfqyDCmsbVDt9VBV1QK
pQpu6DO1MMc4CTl39SoXN67x0DveTqVcI3FTOq0+m5ubNFst4jhGaBpSEcRZ
ip3LIxWBnXcYuh6FQoEwijh58iRHVxbp7q2SZJK9ccL8rW+iGejUj97Bt3/f
h7/jOnAHa9nDde1hic4OybL8quW3Vp9Vsr3L2ac/+geErkvVNGjt7OH220xV
K4ySIYqi4Y59crkiXS8kSyXjYMxWw6U/2o9LKYI0zrBSlbydo1yexg9cBt0+
rc6IJJUUChaqoROnKUHosbNxjSBKCL2AYRoRhSFJkCLzJroGSQCObVGamwNv
QPvqVSrlPHNvfTvRxQsEAqI4pb3XoN0fUsgVKNeqaJqON3YJkgAv9Gi2W9z7
4P2s7W6zsrhAY3uX3bVtCkaRNM5wdJ16tYKiKNi5PKppkAkoV6q4vgeqsl/v
pglN36O5vUUWjJmbLpMrltjpbyITSb8/xLt2DaB0HUTj+j28joV6qL69UUdF
9loyrL2epOiRz/wlzz3zFKdnJpGjFhdfeREtSyiYJoVCCcfJc+XqGnEUEPkB
0xMTJCk0O238ICGfL2CYNqqqYth5MqHhhdAfxPR6Pr4vMXMmVq6Aoij4vk+S
JLT2xjgOmAqYSoZQMuIYglFI6MLSooljGoy21kmTgIn5eTJ3QHrhAkatipGk
oBt4/SGrjcv09QErR45QmZpAz1m0223CNCEZjfj4x/6UpeNHCVavUnGK7O42
2N6+Rq1cY6JcxpiaxDRsrJwNukqSSmbm5ygUi5g5m26vz3A8Yux77O42uHDh
HHec+FZGYczxoydo9IZM1WZRSpXsY3/8f/+797zvAz8DjAD3ugOl3qAfSt4g
WXrNhOk1mfrpP/jN7LHP/Bl2GnHp3Avo8ZjjR5YJxkOaey1KpRjfi1hdXSMI
AqIgREpBoVRB0VQSGRFEEaCQy9kgbFwvIm2MyTKFJDURqoVQDKIkJUpiotDH
NgymiuB7sLEHeSPg9AmLh950K/fecxfVcgmZxuw1tpmtL4Iw2bh4npxlMDFR
A91gvLdFfnmFxTN3Ui4U2draojfsETkFalM1Xr50gfrMDK7r8pZ7H2Cv2eLe
O+5kNBoxV53k8iuXcZwCQmb0Wk3iKMV2cth5B1UzGOdsijkbS+SwVJVBEDJV
KGGk0G/usrm+RSAF00cn2bq8yp0rZxhKI1q7tr4HVA8Aqd7AO5aHSpwbOU03
ZKv2WoZ8c2uTva11jtVLBIGPDFzyOZvIHZHL5QiCiP7Ax9BzCHTGo4DN7Qbz
ikW1WiVM28RRgudGhJEklQaBG6NpKWmaoOkaOaeMYahkKfiBy2jYQ0OipPDm
M/O8+9umWFpaYLY+i5QpmqoS+SPc8YByIQe6gBQW77kbAo+tl19gXgjypTLE
CVQrFO+7j1sae1x74Xl8LyRXLHDXfd/CE088wcLsHGmacvrYCa5du8bSzBzP
PXOW5YUFdN1gOB7R73Xwxh5Ckdi2iaLr7G1t4g4HVCcnEKrGpVfOkWYZqqpj
KCr93piZI0cAjWqxhqrqxH6abG/vDBVFcbIs+3L5oh5i4MFFeO36zzeyH+Ub
XaURgPitf/VzP/v044/Q3d7gtuPLOIZGr9mg2+pQzBdRVRPPCzEsC0XRQQrc
sY+qqVQmqsRpSiYF43GA58XEiYLnRmRSpdsdomk6ilBIkogkDvD9Me54TOwl
1HJw3123c9upU8zPzWBaJpE7RBfg5C0KlTLDdpN4PCTxXcY7O+RUheLcLHgB
qBpxvwu9HooqwMmTIyNMIhJFMn/6FMFwyMsvn8PQdPa2tynmcoy6QzrNJuVa
hZzjoOsaIDFMg+pEldpEFSefByR+4JGRYdk2q6tX6fa7+J6PFHDi1Glm5ldw
ypPMHz9NexQSovrPvvTyxsuvnG9nWaYeqE051Pt0M7fpNU0I9dViqRztZFZ9
guc/8zAvPvscR+bqFCyd0HWJw5DGXotCsYLnh/h+wnA4IpcrEPgRUkhqUxOk
MkXXTDwvwvcSkhTCMENRddJ436UZDvrs7e4xHo6QWYiuQdGGD7/nezl12y1Y
QuKP9oEL3CG6JtANHUjJT9bQ4xDbtkmjiJ3Ndcw0w3dd+u02hmagaipKkoCu
o+UdLE0ljCN21je54943cevxk1iGyYmVY8RBSBLGVCsVYinRTX1/QWE8Ikgi
NMtA0w1SmRJlKa12m26vR5LEbG5vY1kWqqGRSolh5dnrDChOznLi9nt4ZW0n
3RmMtj7+5w9fGgyHJEmiXs9uDwOa3sBxuhG44o3GVCEKs2rq7T09HLl333Hn
bVSqE6xfeAER+hRyOZaPnCTLFKIY0ixAU03SJGO6PsNea4fnnz9LqVqh1exT
ry+hqT7nXtpiarJGp9miPRiR02BqqkDoQd6GD7zvPSwv19lZvYxIY7JeD6Xg
YKcaUeBSKzoIywIZkQzGaI6DlrOQvk/BsSnUTkAQ0Om4lJ0iG2vXqE5OUTtx
DAa9fVbVqkxP1JhGgfo0UaOJpqv7a7ZhSD5nY+ULPHn2ORJV4LoumqGzvrnJ
dDqL0DVm5mbR44RStcQzZ59nsZhnt7XH8vIyTs4kU3QGbsDEwiznL68yffoe
Jmfn07ULlzMppVIul0u+748B50Ds/HK9ah4ob7RDa7YHpVi+UaYKQPwfP/U/
/PriTJ3W7jbjfptapcTy/DxJnLK2vsneXpPB0CWJM3zfx3VddE2jVCpgWyo5
26JWm9hvu0wkWZqQxCmKIpislogjl0E/YpzA/XfOc2JlkfGgR2NjjaNzc6gy
Q4QBQqSopRKiVtl/l1Gf8XCAqQgwdISqQBSSBT5C1clVq2RBABIkAqfgQLGA
3++zvblFMB6Tn1+E7W2ElFx45TwXz19AVRTGoxF2IYeXxTR6XXabDaSAME4o
VStMTddZWjnC1PQ0jz35BEIorK6vgSIwbYtTt5xG1S0Us8DVrQa1uUXueOhb
affGbLc6g7XNLc/3fb3X6325HpU3aGJLbuIRZ68lwcprlTRhqqA6Rb71O9/N
VquHVShjFkrU6tOkQiGMEqRQsZwclmWRJSkCWF5aYGl+jpnJKseWF3EsHVWm
VIoWUvoYusRQE04eW+CBb1nh3pMOS3Mz7G1usHruFUyh0trdY9DrE/oBoe+T
tFrE11YZrl5ic/3afq0a+xB4kCWkcchw0GPc7YA7JnA9yqUSaRKxc20V+kOE
hNAd44+G0G7SbzUxCkVOnz7NyrEV5pYWyJXyrG9vIVWFFEmGQOgGc0uLzC0t
kgAvvPQSQlUIoohipcxwPOLue+7lzJ13c9vtZ/j27/xO6gtLPH/hEomqIy0H
hMC2bWtqarJgGEbuep1qXr8fHtoNWPq6OiW0V2EpgLCmlqxLT306KM8souVL
NLpD8pbNOIi45dbb6Hb7kKokSYrIJGHgI5MEU1XIYolj24g0RiQBpAGqGjM/
U8UwLWScYFsKZD55Q9DYXKNSzNFp7BDmbe45cRJNQBj6DFo9wjDAye8v3c3P
TRPHMZHn4Y9GGIaJqqqYioY7HtHtdLBzBZxiCSEEO1vbhHHC9Pwcs5N1/DAA
O0f5llugOyC/sIBlmjQaDY6ePsnQ83jiueexcnnyxZB+v4+iKJRKJcrlCs1m
k729PW6//QytVotquYKuaQghePHFF5k/dppCrYpdKjO7dGSfWKqq5AuFwuzs
bO3zjz66ex2ww2DqrwPQN9yjdPCXFUD5hV/4+f9NZDG3njrOx//ko/RaTUqF
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
qXp0RlfZbZyl2X8ZL71CxAZhtkaQ7LC1u0omoFAuIXSNgTek3esQpRGViQpB
HBCEHp4/YjTuMXb7+L67L9GKitt1CVMTqTpop+7g1G1nGLo+48AHXSFLQuI4
JE0TZJrtjyQjizKUMENzQwwvwghilEwyMCUDM4U0I0oTBkpAf9Jiyx+QWip7
aoizMEPVLNJsd/2nz7407Pb60YF4mt2gpHkj4PL1Kmn+S3ClzeTs/lpk3jLw
29tMFPI0ByFNN6U2M4dmqDzwtgeoL82iO3lGQcLF1W2eff4ibiioTEyjWgqp
4uEmTdxoCzfeJpZNFHOAlU/RbB3LyRPJlLHngqZj5nOMA5e1jXUyMlL2kxWQ
pDIlzRKiJCSLE2Ilzyg28aXN1jMv8+gTzxIrGtXpGbzRkCSJSNMYmUWILEVI
BZFJRAIilhAlEMQQRiRxSJBFhDLdb/BWBEOZklUKKFLFKOUZOhqyWoRiPuv1
R7EfBFmaZvIm8fTVwHy1xfGvK1P/6lsilKWiPbFMvlShWDCJuns4AmLF4a63
fhefffQx9lpNFo8d47NfeJIraw1O3Ho/k9O38vTZDZ58+gq9kaQ9cAmSmEwL
CdMBvdEOncEWftghFSGu7zH2Y/w4IVMUEALX88iQzC7ME2cxUmSo+n7XoGEY
pGlMf9BjY7vBVsOlOnuajz/8BN//oR/n/Oomlalpzl08T256gowUSYyU+7sK
lEyiZAq6VFBTcX2aY9Iswo8DRBCjRCmpqiJ1HduwMVoxJQy0kytkc1OMNYHH
vo7HcSxvUOe/GrDpDdZT3/Dhz9pXJ79ISrPodo52Y5fFqXkuuBG9fsTUwkmE
avKhH/phfvwnfoqZyQnq1WnKxTJvefP9fN97/yF3P3AnQWcTa7iNF3UZDJuM
/TFCt8gX8khUhgOPlAJZpuB5Kd1hm6uXLvLUU09hGBbvePu3cebMXQRBSBon
qESMx2OyLMHUVYQqyNcW+NF//L/SGa1jFPJsNDt0Z3xuW16m39jDtHUQKkKm
yDRBCGX/iHchQEgQGYgMmSUoSYpQJAoCHYgTDTlMMa7zorexTkPRKE+ViEBm
AqI4vlGLyuF10+RVLME3tDj+RkA93AUuAcT88drZD36gs3X1M1hOjrImcP2U
f/iP/xmf+PP/wNnnHufXfv13+dgf/QkXX7rChfPXWLvs8+v/9o85emSad3/v
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
FzquFzZJty1W39vYqftlO0mnHPt1FeWLIhL5wotXn6bQs3oVLhDTNZJhlf6E
Sks8iSYlmJ/2eeDexxFOhJ72AQ6PHOb8c88hGjUol8tEI0lUKcb3vvMwdhU0
OYrneLSk07S1Jrn4wo38xg1v5orLL2Jm5jCK4lApzlIuzTI5cZh9L+ykp7uN
XGGGzVdeRsUq0r+8m6MzE0QiKp/+1MfxnRJnrezFUATMZZEQHDx4ENM0QcgI
UTO9IeD6Pq7rnzzQZd3syoX4kozZmcBOqJiBF1YtM3AcN2yivhOBPeVq/Fec
etOD4EO9kqT94lVBpqMDB4GkaMgutMoanZJH1C2TjGRATvNPX/waupYgGWth
17P7mRkvYhYER0az/NVf/S3bntvO6OQoo5NjhEKikK8ioVMuFznn3CEu23QR
+VwWQ9colYq4joXnWPR2L2NsbBTHrTK4oo/u3mVUzCp6LEoun+O3b7uJXbt+
zpZnnkSSXDg6gTs9xUBnO55v4cshISGyFxCYLrbjntLJy88V6UBF6UhS7IsT
xiMUqlU/Xyz5juMGDSUsQRMT3OxeCq9wLtwpxX47VfXLL/mjqkIsFiHZ3o4d
qoRuBrUqc2EL6KU9uKGNbcT40ZNPc3B4AuEYtMWWk5CWkz3ic9stH+Pub9/L
4Po+jJaQ/rO6kHSZYjHE9+LEE2nGpyc5MDzC2nUbsOyAaCRFdjZPT3d/rWW6
EFSrVVo72snmC7iSjBJJoRhxRvfu4sMfuZl4W4R0TGZ++3bS2XmsmQmMCASS
h/yychrgSxK9vkEsqGL26OQTMr6kBtt27i4Mj45VnVqIsJlS/ZNwlk64su10
Z2le4vplOttxFfBUlUDSUENIU2KZbJGIyxSqBSRdZmR8HOQ4LxyY5Etfvoe/
/+xXOTpX4KrrruW/f/Lj9Cxvp2LlqdoW69ZegKakyBYKtHZ20N7ZRaFYZtXK
NSxfvpJkIoNp2sxn52lrb6Gvrw9JkqjaFkgKiqoT1m75LO/tRsZnbnqauZFR
Bto6aGlvI4xqyHVG51S3uNDRbA9ZCvDTOp4uU6iUvalszimWK14YhkGTRVDB
SYAVr1Spr2wujSIjD/QTqCqeUkuEEToYqk5XW4SJygxIMqZb4rNf+N88sWUN
kxNH2b17kmLRJZ5IMTeX5d5v3cPc1DQ/ffwJrt58FePjk1TKJq3tnRRLWRzL
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
EOF
end

