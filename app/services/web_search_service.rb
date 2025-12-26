# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'nokogiri'

class WebSearchService
  # Use DuckDuckGo HTML scraping (free, no API key required)
  # Alternative: Can use Google Custom Search API if API key is provided
  DUCKDUCKGO_API = 'https://api.duckduckgo.com/'
  DUCKDUCKGO_HTML = 'https://html.duckduckgo.com/html/'
  GOOGLE_SEARCH_API = 'https://www.googleapis.com/customsearch/v1'

  def self.search(query, max_results: 5)
    new.search(query, max_results: max_results)
  end

  def search(query, max_results: 5)
    return { error: 'Query cannot be blank' } if query.blank?

    # Try DuckDuckGo HTML scraping first (free, no API key, better results)
    results = search_duckduckgo_html(query, max_results: max_results)

    # If HTML scraping fails, try DuckDuckGo API (fallback)
    if results[:error] || results[:results].empty?
      api_results = search_duckduckgo(query, max_results: max_results)
      results = api_results unless api_results[:error]
    end

    # If still no results, try Google Custom Search if API key is available
    if (results[:error] || results[:results].empty?) && google_api_key.present?
      google_results = search_google(query, max_results: max_results)
      return google_results unless google_results[:error]
    end

    # Enhance results by scraping content from top URLs
    enhance_with_content(results) if results[:results]&.any?

    results
  rescue StandardError => e
    Rails.logger.error("[WebSearchService] Error: #{e.class} - #{e.message}")
    { error: "Search failed: #{e.message}", results: [] }
  end

  private

  def search_duckduckgo_html(query, max_results: 5)
    # DuckDuckGo HTML scraping (free, no API key, better results)
    uri = URI(DUCKDUCKGO_HTML)
    uri.query = URI.encode_www_form(q: query)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 15
    http.open_timeout = 10

    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'

    response = http.request(request)

    if response.code == '200'
      doc = Nokogiri::HTML(response.body)
      results = []

      # DuckDuckGo HTML structure: results are in div.result
      doc.css('div.result').first(max_results).each do |result|
        title_elem = result.at_css('a.result__a')
        snippet_elem = result.at_css('a.result__snippet') || result.at_css('div.result__snippet')

        next unless title_elem

        title = title_elem.text.strip
        url = title_elem['href']
        snippet = snippet_elem&.text&.strip || ''

        # Clean up URL (DuckDuckGo uses redirect URLs)
        url = extract_real_url(url) if url

        results << {
          title: title,
          snippet: snippet,
          url: url,
          source: 'DuckDuckGo'
        }
      end

      { results: results, query: query }
    else
      { error: "DuckDuckGo HTML returned #{response.code}", results: [] }
    end
  rescue StandardError => e
    Rails.logger.error("[WebSearchService] DuckDuckGo HTML error: #{e.message}")
    { error: "DuckDuckGo HTML search failed: #{e.message}", results: [] }
  end

  def search_duckduckgo(query, max_results: 5)
    # DuckDuckGo Instant Answer API
    uri = URI("#{DUCKDUCKGO_API}?q=#{URI.encode_www_form_component(query)}&format=json&no_html=1&skip_disambig=1")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    if response.code == '200'
      data = JSON.parse(response.body)
      results = []

      # Extract Abstract (if available)
      if data['AbstractText'].present?
        results << {
          title: data['Heading'] || query,
          snippet: data['AbstractText'],
          url: data['AbstractURL'],
          source: 'DuckDuckGo'
        }
      end

      # Extract Related Topics
      if data['RelatedTopics'].is_a?(Array)
        data['RelatedTopics'].first(max_results - results.length).each do |topic|
          next unless topic.is_a?(Hash) && topic['Text'].present?

          results << {
            title: topic['FirstURL']&.split('/')&.last&.tr('_', ' ') || query,
            snippet: topic['Text'],
            url: topic['FirstURL'],
            source: 'DuckDuckGo'
          }
        end
      end

      { results: results.first(max_results), query: query }
    else
      { error: "DuckDuckGo API returned #{response.code}", results: [] }
    end
  rescue StandardError => e
    Rails.logger.error("[WebSearchService] DuckDuckGo error: #{e.message}")
    { error: "DuckDuckGo search failed: #{e.message}", results: [] }
  end

  def search_google(query, max_results: 5)
    return { error: 'Google API key not configured', results: [] } unless google_api_key.present?
    return { error: 'Google Search Engine ID not configured', results: [] } unless google_search_engine_id.present?

    uri = URI(GOOGLE_SEARCH_API)
    params = {
      key: google_api_key,
      cx: google_search_engine_id,
      q: query,
      num: max_results
    }
    uri.query = URI.encode_www_form(params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    if response.code == '200'
      data = JSON.parse(response.body)
      results = (data['items'] || []).map do |item|
        {
          title: item['title'],
          snippet: item['snippet'],
          url: item['link'],
          source: 'Google'
        }
      end

      { results: results, query: query }
    else
      error_data = begin
        JSON.parse(response.body)
      rescue StandardError
        {}
      end
      { error: "Google API error: #{error_data['error']&.dig('message') || response.code}", results: [] }
    end
  rescue StandardError => e
    Rails.logger.error("[WebSearchService] Google error: #{e.message}")
    { error: "Google search failed: #{e.message}", results: [] }
  end

  def google_api_key
    ENV.fetch('GOOGLE_SEARCH_API_KEY', nil)
  end

  def google_search_engine_id
    ENV.fetch('GOOGLE_SEARCH_ENGINE_ID', nil)
  end

  def extract_real_url(duckduckgo_url)
    # DuckDuckGo uses redirect URLs like /l/?kh=-1&uddg=https://example.com
    return duckduckgo_url unless duckduckgo_url&.include?('/l/?')

    begin
      uri = URI.parse(duckduckgo_url)
      params = URI.decode_www_form(uri.query || '')
      uddg_param = params.find { |k, _v| k == 'uddg' }
      uddg_param ? uddg_param[1] : duckduckgo_url
    rescue StandardError
      duckduckgo_url
    end
  end

  def enhance_with_content(search_results, max_content_length: 500)
    # Scrape content from top search results to get more detailed information
    return search_results unless search_results[:results]&.any?

    search_results[:results].first(3).each do |result|
      next if result[:url].blank?

      begin
        content = scrape_page_content(result[:url], max_length: max_content_length)
        result[:content] = content if content.present?
      rescue StandardError => e
        Rails.logger.debug { "[WebSearchService] Failed to scrape #{result[:url]}: #{e.message}" }
        # Continue with snippet if scraping fails
      end
    end

    search_results
  end

  def scrape_page_content(url, max_length: 500)
    return nil if url.blank?

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 10
    http.open_timeout = 5

    request = Net::HTTP::Get.new(uri.path.empty? ? '/' : uri.path)
    request['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    request['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'

    response = http.request(request)

    return nil unless response.code == '200'

    doc = Nokogiri::HTML(response.body)

    # Remove script and style elements
    doc.css('script, style, nav, header, footer, aside').remove

    # Try to extract main content
    # Look for common content selectors
    content = nil
    %w[article main .content .post .entry-content #content].each do |selector|
      elem = doc.at_css(selector)
      if elem
        content = elem.text.strip
        break
      end
    end

    # Fallback to body text if no main content found
    content ||= doc.at_css('body')&.text&.strip

    return nil if content.blank?

    # Clean up: remove extra whitespace, limit length
    content = content.gsub(/\s+/, ' ').strip
    content = content[0..max_length] + '...' if content.length > max_length

    content
  rescue StandardError => e
    Rails.logger.debug { "[WebSearchService] Scraping error for #{url}: #{e.message}" }
    nil
  end
end
