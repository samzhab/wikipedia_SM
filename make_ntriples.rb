#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'addressable'

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
  puts '[INFO] finished processing files '
end

def make_page_id_nt(tsv_file_name)
  nt_path = Dir.pwd + '/nt_files/' + tsv_file_name + '.nt'
  nt_file = File.new(nt_path.remove('.tsv'), 'w') # create nt file without .tsv
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
  puts '[INFO] finished with --- ' + tsv_file_name
  nt_file.close
  tsv_file.close
end

def make_doi_nt(tsv_file_name)
  nt_path = Dir.pwd + '/nt_files/' + tsv_file_name + '.nt'
  nt_file = File.new(nt_path, 'w') # create nt file same name
  tsv_file = open(Dir.pwd + '/tsv_files/' + tsv_file_name)
  log_file = File.new(Dir.pwd + '/log/' + Time.now.to_s + '.txt', 'w')
  crossref_uri = URI('https://api.crossref.org/v1/works/http://dx.doi.org/')
  property_url = 'http://purl.org/dc/terms/title'
  Net::HTTP.start(crossref_uri.host, crossref_uri.port) do |_http|
    while (line = tsv_file.gets)
      next unless line.split(' ').last.include?("\/")
      id = line.split(' ').last if line.split(' ').last.include?('10.')
      crossref_url = 'https://api.crossref.org/v1/works/http://dx.doi.org/'
      formed_uri = crossref_url + id
      formed_uri = Addressable::URI.encode(formed_uri.strip)
      formed_uri = Addressable::URI.parse(formed_uri)
      puts '[INFO] processing ---> ' + id + ' from [' +
           tsv_file_name.to_s + ']'
      puts '[INFO] looking for resource ---> ' + formed_uri
      formed_uri = URI(formed_uri)
      response = Net::HTTP.get_response(formed_uri)
      response = check_response(response, id, crossref_url, log_file)
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
          log_file.puts '[INFO] [' + Time.now.to_s + '] saved triple ---> ' +
                        n_triple + ' using doi [' + id + '] from [' +
                        tsv_file_name + ']'
        end
      end
    end
  end
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
    formed_uri = Addressable::URI.encode((c_url + recheck_id).strip)
    formed_uri = Addressable::URI.parse(formed_uri)
    # formed_uri = URI.parse(URI.encode(formed_uri.strip))
    puts '[INFO] re-trying again as --- ' + formed_uri.to_s
    formed_uri = URI(formed_uri)
    response = Net::HTTP.get_response(formed_uri)
    check_response(response, recheck_id, c_url, log_file) unless
    formed_uri.to_s == c_url.to_s
  end
end
start
