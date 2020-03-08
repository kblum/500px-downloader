require 'logger'
require 'httparty'
require 'nokogiri'
require 'json'
require 'mime/types'

class Downloader

  def initialize(url)
    @url = url
    @loaded = false
  end

  def logger
    if @logger.nil?
      @logger ||= Logger.new(STDOUT)
      @logger.level = Logger::DEBUG
    end
    @logger
  end

  def run
    logger.info("Downloading: #{@url}")
    image_id = extract_id(@url)
    raise StandardError.new("Unable to extract image ID for #{@url}") if image_id.nil?
    logger.info("Image ID: #{image_id}")
    
    json_metadata_url = "https://api.500px.com/v1/photos"
    json_metadata_query = {
      ids: image_id,
      image_size: [2048],
      include_states: 1,
      expanded_user_info: true,
      include_tags: true,
      include_geo: true
    }
    json_metadata_response = fetch(json_metadata_url, json_metadata_query)
    json_metadata = JSON.parse(json_metadata_response.body)
    image_json_metadata = json_metadata['photos'][image_id.to_s]

    image_url = image_json_metadata['image_url'].first
    raise StandardError.new("Unable to extract image URL for #{@url}") if image_url.nil?

    image_title = image_json_metadata['name']
    author_name = image_json_metadata['user']['fullname']
    logger.debug("Image title: #{image_title}")
    logger.debug("Author name: #{author_name}")
    clean_image_title = "#{image_title} by #{author_name} - 500px-#{image_id}"
    clean_image_title = clean_image_title.gsub(/\s+/, ' ') # collapse multiple spaces
    logger.debug("Title: #{clean_image_title}")

    image_response = fetch_image(image_url)

    image_headers = image_response.headers

    image_extension = extract_image_extension(image_headers)
    raise StandardError.new("Unable to extract image extension for #{@url}") if image_extension.nil?
    # build filename with extension (`image_extension` already contains the ".")
    filename = "#{clean_image_title}#{image_extension}"

    logger.debug("Filename: #{filename}")

    output_path = File.join(File.dirname(__FILE__), output_dir, filename)
    logger.info("Saving file to: #{output_path}")
    save_image!(output_path, image_response)
  rescue => exception
    logger.error(exception)
    raise
  end

  private

  def output_dir
    dir_name = 'output'
    dir = File.join(File.dirname(__FILE__), dir_name)
    Dir.mkdir(dir) unless Dir.exist?(dir)
    dir
  end

  # Extract image ID from image URL
  # Example URLs: 
  #   https://500px.com/photo/123456789/Photo-Title-by-Author-Name
  #   https://web.500px.com/photo/123456789/Photo-Title-by-Author-Name/
  # ID => 123456789
  def extract_id(image_id)
    regex = /500px\.com\/photo\/(\d+)\//
    matches = regex.match(image_id)
    return nil if !matches
    match = matches[1]
    return nil if match.empty?
    match
  end

  def extract_image_extension(headers)
    # examples for headers:
    # content-type => "image/jpeg"
    # content-disposition => "filename=stock-photo-123456.jpg"

    content_type = headers['content-type']
    content_disposition = headers['content-disposition']

    unless content_disposition.nil?
      image_extension = File.extname(content_disposition) # => ".jpg"
      return image_extension unless image_extension.nil?
    end

    image_extension = MIME::Types[content_type].first.extensions.first
    unless image_extension.nil?
      image_extension = 'jpg' if image_extension.downcase == 'jpeg' # normalise
      return ".#{image_extension}"
    end

    nil # cannot extract image extension
  end

  def fetch_image(image_url)
    # attempt to download full image (potentially larger than current image URL)
    # replace "/styles/ANY/" with "/styles/full/"
    desired_size = 'full'
    image_url_full = image_url.gsub(/(\/styles\/)(\w*)(\/)/, "\\1#{desired_size}\\3")
    begin
      return fetch(image_url_full)
    rescue
      logger.debug("Unable to download full image '#{image_url_full}'; reverting to '#{image_url}'")
    end

    # download given image
    fetch(image_url)
  end

  def fetch(url, query=nil)
    logger.debug("Loading URL: #{url}")
    response = query.nil? ? HTTParty.get(url) : HTTParty.get(url, query: query)
    raise StandardError.new('HTTP request unsuccessful') unless response.success?
    response
  end

  def save_image!(output_path, image_response)
    File.open(output_path, 'wb') do |f|
      f.write(image_response.body)
    end
  end

end

# download each URL supplied as a command-line argument
urls = ARGV
urls.each do |url|
  begin
    Downloader.new(url).run  
  rescue
    # ignore failures
  end
end
