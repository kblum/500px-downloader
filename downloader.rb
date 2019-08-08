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
    page_html = fetch(@url).body
    document = Nokogiri::HTML(page_html)

    image_url = extract_image_url(document)
    raise StandardError.new("Unable to extract image URL for #{@url}") if image_url.nil?

    page_title = document.at("title").text
    image_title = document.at("link[rel='alternate']")['title']
    image_title = image_title.gsub(/\s+/, ' ') # collapse multiple spaces

    logger.debug("Page title: #{page_title}")
    logger.debug("HTML - og:image: #{image_url}")
    logger.debug("image title: #{image_title}")
    logger.debug("HTML - og:title: #{parse_meta_tag_content(document, 'og:title')}")

    image_response = fetch(image_url)

    image_headers = image_response.headers

    image_extension = extract_image_extension(image_headers)
    raise StandardError.new("Unable to extract image extension for #{@url}") if image_extension.nil?
    
    # page_title => "Title by Author - Photo 123456 / 500px"
    # clean up title for filename by replacing "Photo 123456 / 500px" with "500px-123456"
    /Photo\s(?<image_id>\d+)\s\/\s500px$/ =~ page_title # extract image ID from title
    clean_image_title = page_title.gsub(/Photo\s\d+ \/ 500px$/, "500px-#{image_id}")
    clean_image_title = clean_image_title.gsub(/\s+/, ' ') # collapse multiple spaces
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

  def extract_image_url(document)
    image_url = parse_meta_tag_content(document, 'og:image')

    # handle images where `image_title` => "https://500px.com/graphics/nude/img_3.png"
    if image_url =~ /500px\.com\/graphics\/nude\/.*/
      # find appropriate script tag and extract JSON string for photo
      matches = document.search('script').map {|script| script.text.match(/window\.PxPreloadedData\s?=\s?(.+);/)}.compact.first
      return nil if matches.nil?
      preloaded_data_string = matches&.captures&.first
      return nil if preloaded_data_string.nil?
      preloaded_data = JSON.parse(preloaded_data_string)

      # get images array from JSON data
      images = preloaded_data.dig('photo', 'images')
      # sample of image element JSON schema:
      #
      # {
      #   "format": "jpeg",
      #   "https_url": "...",
      #   "size": 1|2|4|35|2048|...,
      #   "url: "..."
      # }
      return nil if images.nil? || images.empty?

      # extract all JPG images
      images = images.select {|i| ['jpeg', 'jpg'].include?(i['format'])}
      # find largest image
      image = images.max_by {|i| i['size']}
      return nil if image.nil?

      image_url = image['url']
    end

    image_url
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

  def fetch(url)
    logger.debug("Loading URL: #{url}")
    response = HTTParty.get(url)
    raise StandardError.new('HTTP request unsuccessful') unless response.success?
    response
  end

  def parse_meta_tag_content(document, property)
    document.at("meta[property=\"#{property}\"]")['content']
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
