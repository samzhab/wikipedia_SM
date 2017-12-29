#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'addressable'
require 'rest-client'

def start
  tsv_files = Dir.entries(Dir.pwd + '/tsv_test/') # list of files
  threads = []
  doi_files = []
  puts '[START] started extracting all dois to separate files '
  tsv_files.each do |tsv_file_name|
    next if (tsv_file_name == '.') || (tsv_file_name == '..') # skip these
    threads << Thread.new do
      puts '[INFO] extracting dois from ' + tsv_file_name.to_s
      doi_files << extract_doi_to_file(tsv_file_name)
    end
  end
  threads.each(&:join)
  puts '[END] finished extracting all dois to separate files '
  threads = []
  puts '[START] started composing n-triples from dois '
  doi_files.each do |doi_file|
    threads << Thread.new do
      make_doi_nt(doi_file)
    end
  end
  threads.each(&:join)
  puts '[END] finished composing n-triples '
end

def make_page_id_nt(tsv_file_name)
  nt_path = Dir.pwd + '/nt_files/' + tsv_file_name + '.nt'
  nt_file = File.new(nt_path.remove('.tsv'), 'w') # create nt file without .
  puts '[INFO] processing --- ' + tsv_file_name
  tsv_file    = open(Dir.pwd + '/tsv_test/' + tsv_file_name)
  while (line = tsv_file.gets)
    page_id = line.split(' ').first unless line.split(' ').first == 'page_id'
    id      = line.split(' ').last unless line.split(' ').last == 'id'
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

def extract_doi_to_file(tsv_file_name)
  doi_path  = Dir.pwd + '/doi_files/' + tsv_file_name + '.doi'
  doi_file  = File.new(doi_path.gsub('.tsv', ''), 'w') # create doi file
  tsv_file = open(Dir.pwd + '/tsv_test/' + tsv_file_name)
  while (line = tsv_file.gets)
    next unless line.split(' ').last.include?("\/")
    id = line.split(' ').last if line.split(' ').last.include?('10.')
    doi_file.puts id
  end
  doi_file.close
  tsv_file.close
  to_return = []
  to_return << doi_file
  to_return << tsv_file_name
  to_return
end

def slice_in_half(doi_file)
  # slice in half and save two files with tsv_file_name
  # return doi_file array appended with the new file name
  middle_section_line = if doi_file[2].even?
                          doi_file[2] / 2
                        else
                          (doi_file[2] / 2).round
                        end
  part_num = doi_file[3]
  part_id = '_part_'
  doi_path = Dir.pwd + '/doi_files/' + doi_file[1] + part_id +
             (part_num + 1).to_s + '.doi'
  doi_part_file = File.new(doi_path, 'w') # create doi file - .tsv
  line_num = 0
  doi_file_to_slice = File.open(doi_file[0])
  while line_num < middle_section_line
    line = doi_file_to_slice.gets
    doi_part_file.puts line
    line_num += 1
  end
  doi_file << doi_part_file
  part_num += 1
  doi_part_file.close # end of first part

  doi_path = Dir.pwd + '/doi_files/' + doi_file[1] + part_id +
             (part_num + 1).to_s + '.doi'
  doi_part_file = File.new(doi_path, 'w') # create doi file - .tsv
  while line_num <= doi_file[2]
    line = doi_file_to_slice.gets
    doi_part_file.puts line
    line_num += 1
  end
  doi_file << doi_part_file
  doi_part_file.close # end of second part

  doi_file_to_slice.close
  part_num += 1
  doi_file[3] = part_num
  doi_file
end

def make_doi_nt(doi_file)
  doi_file[1] = doi_file[1].gsub('.tsv', '')
  nt_path     = Dir.pwd + '/nt_files/' + doi_file[1] + '.nt'
  nt_file     = File.new(nt_path, 'w') # create nt file - .tsv
  log_file    = File.new(Dir.pwd + '/log/' + Time.now.to_s + '.txt', 'w')
  line_num    = File.open(doi_file[0], &:count)
  doi_file << line_num
  doi_file << 0 # parts counter "doi_file[3]" no parts of this file
  doi_file = slice_in_half(doi_file)
  puts '[INFO] composing n-triples from dois '
  doi_part_files = []
  doi_part_files << doi_file[4]    # part 1
  doi_part_files << doi_file[5]    # part 2
  threads = []
  doi_part_files.each do |doi_part_file|
    range                = 1..25
    max_to_process       = 0
    doi_part_file_lines  = File.open(doi_part_file, &:count)
    range.each do |num|
      if (doi_part_file_lines % num).zero?
        max_to_process = doi_part_file_lines / num
      end
    end
    threads << Thread.new do
      all_ids        = []
      all_urls       = []
      doi_part_file  = File.open(doi_part_file)
      crossref_url   = 'https://api.crossref.org/works/'
      while (id      = doi_part_file.gets)
        formed_url = crossref_url + id
        formed_url = Addressable::URI.encode(formed_url.strip)
        formed_url = Addressable::URI.parse(formed_url)
        formed_url = URI(formed_url)
        all_ids << id
        all_urls << formed_url
        next unless all_ids.size == max_to_process # if equal pause and do >
        setup_process(all_ids, all_urls, nt_file, log_file)
        all_ids    = []
        all_urls   = []
      end
      doi_part_file.close
    end
  end
  threads.each(&:join)
  log_file.puts '[END] [' + Time.now.to_s + '] finished with ---> '
  nt_file.close
  log_file.close
end

def setup_process(all_ids, all_urls, nt_file, log_file)
  max_to_process = 10
  counter = 0
  ids_to_process = []
  urls_to_process = []
  if all_ids.size > max_to_process
    max_to_process = all_ids.size % max_to_process
    range = counter..max_to_process
    range.each do |num|
      ids_to_process << all_ids[num]
      urls_to_process << all_urls[num]
      counter += 1
    end
    execute_process(ids_to_process, urls_to_process, nt_file, log_file)
    ids_to_process = []
    urls_to_process = []
    while counter < all_ids.size - 1
      range = counter..(counter + 10)
      range.each do |num|
        ids_to_process << all_ids[num]
        urls_to_process << all_urls[num]
        counter += 1
      end
      execute_process(ids_to_process, urls_to_process, nt_file, log_file)
      ids_to_process = []
      urls_to_process = []
    end
  end
end

def execute_process(ids_to_process, urls_to_process, nt_file, log_file)
  threads = []
  crossref_uri = URI('https://api.crossref.org/works/')
  # crossref_url = 'https://api.crossref.org/v1/works/http://dx.doi.org/'
  property_url = 'http://purl.org/dc/terms/title'
  Net::HTTP.start(crossref_uri.host, crossref_uri.port) do |_http|
    range = 0..ids_to_process.size - 1
    range.each do |num|
      threads << Thread.new do
        id = ids_to_process[num]
        url = urls_to_process[num]
        puts '[INFO] processing ---> ' + id.to_s
        # response = Net::HTTP.get_response(url,{}) if url && !url.nil?
        # response = check_response(response, id, crossref_url, log_file)
        if url && !url.nil?
          begin
            response = RestClient::Request.execute(method: :get,
                                                   url: Addressable::URI
                                                     .parse(url)
                                                     .normalize.to_str,
                                                   timeout: 300)
          rescue RestClient::ExceptionWithResponse => e
            puts e.response
            # response = recheck_url(id, crossref_url, log_file)
          end
        end
        # puts '[ERROR] resource not found ' unless response
        log_file.puts '[ERROR] resource not found ' + id.to_s unless response
        next unless response # skip to next in all_urls
        # puts '[ERROR] resource not found ' unless response
        # log_file.puts '[ERROR] resource not found ' + id.to_s unless response
        json_response = JSON.parse(response.body)
        case json_response['status']
        when 'ok'
          titles = json_response['message']['title']
          titles.each do |title|
            n_triple = '<http://dx.doi.org/' + id.strip + '>' + ' <' +
                       property_url + '> ' + title.inspect.to_s + '.'
            nt_file.puts n_triple
          end
        end
      end
    end
    threads.each(&:join)
  end
end
# def recheck_url(recheck_id, c_url, log_file)
#   recheck_id = recheck_id.split('/')
#   recheck_id.pop # remove last part
#   recheck_id = recheck_id.join('/')
#   formed_url = c_url + recheck_id
#   # split id and try again
#   # eg. remove 'abstract' from doi	10.1002/jid.1458/abstract, try again
#   puts '[INFO] re-trying again as --- ' + formed_url.to_s
#   begin
#     response = RestClient::Request.execute(method: :get,
#                                            url: Addressable::URI
#                                                 .parse(formed_url)
#                                                 .normalize.to_str,
#                                            timeout: 300)
#     puts 'SUCCESSFUL'
#     puts formed_url
#   rescue RestClient::ExceptionWithResponse => e
#     recheck_url(recheck_id, c_url, log_file) unless
#     formed_url.to_s == c_url.to_s
#   end
# end

# def check_response(response, recheck_id, c_url, log_file)
#   case response
#   when Net::HTTPSuccess then
#     response
#   when Net::HTTPNotFound then
#     # split id and try again
#     # eg. remove 'abstract' from doi	10.1002/jid.1458/abstract, try again
#     # :TODO refactor splitting to a new method
#     recheck_id = recheck_id.split('/')
#     recheck_id.pop # remove last part
#     recheck_id           = recheck_id.join('/')
#     formed_url           = Addressable::URI.encode((c_url + recheck_id).strip)
#     formed_url           = Addressable::URI.parse(formed_url)
#     # formed_url = URI.parse(URI.encode(formed_url.strip))
#     puts '[INFO] re-trying again as --- ' + formed_url.to_s
#     formed_url           = URI(formed_url)
#     response             = Net::HTTP.get_response(formed_url)
#     check_response(response, recheck_id, c_url, log_file) unless
#     formed_url.to_s == c_url.to_s
#   end
# end

start
