#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'addressable'
require 'rest-client'

def start
  tsv_files = Dir.entries(Dir.pwd + '/tsv_files/') # list of files
  tsv_files.each do |tsv_file_name|
    next if (tsv_file_name == '.') || (tsv_file_name == '..') # skip these
    puts '[INFO] found --- ' + tsv_file_name
    puts '[INPUT] what would you like to do with these? \
                  Z - make page_id triples
                  X - make doi title triples'
    # choice = gets.chomp                   # uncomment for user interaction
    choice = 'x'
    case choice
    when 'z'
      make_page_id_nt(tsv_file_name)
    when 'x'
      make_doi_nt(tsv_file_name)
    end
  end
  puts '[END] finished processing all files '
end

def make_page_id_nt(tsv_file_name)
  nt_path = Dir.pwd + '/nt_files/' + tsv_file_name + '.nt'
  nt_file = File.new(nt_path.remove('.tsv'), 'w') # create nt file without .
  puts '[INFO] processing --- ' + tsv_file_name
  tsv_file = open(Dir.pwd + '/tsv_files/' + tsv_file_name)
  while (line = tsv_file.gets)
    page_id = line.split(' ').first unless line.split(' ').first == 'page_id'
    id = line.split(' ').last unless line.split(' ').last == 'id'
    next unless page_id # skip first line from tsv file
    n_triple = '<http://en.wikipedia.org/wiki?curid=' +
               page_id +
               ">\t<http://lod.openaire.eu/vocab/resOriginalID>\t\"" +
               id + '"'
    nt_file.puts n_triple
  end
  puts '[END] finished with --- ' + tsv_file_name
  nt_file.close
  tsv_file.close
end

def make_doi_nt(tsv_file_name)
  nt_path = Dir.pwd + '/nt_files/' + tsv_file_name + '.nt'
  nt_file = File.new(nt_path.gsub('.tsv', ''), 'w') # create nt file without .
  tsv_file = open(Dir.pwd + '/tsv_files/' + tsv_file_name)
  log_file = File.new(Dir.pwd + '/log/' + Time.now.to_s + '.txt', 'w')
  log_file.puts '[START] [' + Time.now.to_s + '] started with ---> ' +
              tsv_file_name
  crossref_uri = URI('https://api.crossref.org/v1/works/http://dx.doi.org/')
  property_url = 'http://purl.org/dc/terms/title'
  all_ids = []
  all_urls = []
  while (line = tsv_file.gets)
    next unless line.split(' ').last.include?("\/")
    id = line.split(' ').last if line.split(' ').last.include?('10.')
    all_ids << id
    crossref_url = 'https://api.crossref.org/v1/works/http://dx.doi.org/'
    formed_url = crossref_url + id
    formed_url = Addressable::URI.encode(formed_url.strip)
    formed_url = Addressable::URI.parse(formed_url)
    formed_url = URI(formed_url)
    all_urls << formed_url
  end
  threads = []
  Net::HTTP.start(crossref_uri.host, crossref_uri.port) do |http|
    range = 0..all_urls.size-1
    range.each do |num|
      threads << Thread.new do
        puts '[INFO] processing ---> ' + all_ids[num] + ' from [' +
             tsv_file_name.to_s + ']'
        puts '[INFO] looking for resource ---> ' + all_urls[num].to_s
        response = Net::HTTP.get_response(all_urls[num])
        response = check_response(response, all_ids[num], crossref_url, log_file)
        puts '[ERROR] resource not found ' unless response
        log_file.puts '[ERROR] resource not found for ' + id.to_s unless response
        next unless response # skip to next line if no resource / response
        json_response = JSON.parse(response.body)
        case json_response['status']
        when 'ok'
          titles = json_response['message']['title']
          titles.each do |title|
            n_triple = '<http://dx.doi.org/' + id + '>' + ' <' + property_url +
                       '> ' + title.inspect.to_s + '.'
            nt_file.puts n_triple
          end
        end
        end
    end
  end

  threads.each {|t| t.join}
  log_file.puts '[END] [' + Time.now.to_s + '] finished with ---> ' +
              tsv_file_name
  nt_file.close
  tsv_file.close
  log_file.close
end

def check_response(response, recheck_id, c_url, log_file)
  case response
  when Net::HTTPSuccess then
    response
  when Net::HTTPNotFound then
    # split id and try again
    # eg. remove 'abstract' from doi	10.1002/jid.1458/abstract, try again
    recheck_id = recheck_id.split('/')
    recheck_id.pop # remove last part
    recheck_id = recheck_id.join('/')
    formed_url = Addressable::URI.encode((c_url + recheck_id).strip)
    formed_url = Addressable::URI.parse(formed_url)
    # formed_url = URI.parse(URI.encode(formed_url.strip))
    puts '[INFO] re-trying again as --- ' + formed_url.to_s
    formed_url = URI(formed_url)
    response = Net::HTTP.get_response(formed_url)
    check_response(response, recheck_id, c_url, log_file) unless
    formed_url.to_s == c_url.to_s
  end
end
start
