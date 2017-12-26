#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'addressable'

def start
  tsv_files = Dir.entries(Dir.pwd + '/test_tsv/') # list of files
  threads      = []
  doi_files = []
  puts '[START] started extracting all dois to separate files '
  tsv_files.each do |tsv_file_name|
    next if (tsv_file_name == '.') || (tsv_file_name == '..') # skip these
    # puts '[INFO] found --- ' + tsv_file_name
    # puts '[INPUT] what would you like to do with these? \
    #               Z - make page_id triples
    #               X - make doi title triples'
    # choice = gets.chomp                   # uncomment for user interaction
    # choice = 'x'
    # case choice
    # when 'z'
    #   make_page_id_nt(tsv_file_name)
    # when 'x'
    #   extract_doi_to_file(tsv_file_name)
    #   make_doi_nt(tsv_file_name)
    # end
    threads << Thread.new do
      puts '[INFO] extracting dois from ' + tsv_file_name.to_s
      doi_files << extract_doi_to_file(tsv_file_name)
    end
  end
  threads.each(&:join)
  puts '[END] finished extracting all dois to separate files '

  threads      = []
  puts '[START] started composing n-triples from dois '
  doi_files.each do |doi_file|
    threads << Thread.new do
      make_doi_nt(doi_file)
    end
  end
  threads.each(&:join)
  puts '[END] finished extracting all dois to separate files '
end

def make_page_id_nt(tsv_file_name)
  nt_path = Dir.pwd + '/nt_files/' + tsv_file_name + '.nt'
  nt_file = File.new(nt_path.remove('.tsv'), 'w') # create nt file without .
  puts '[INFO] processing --- ' + tsv_file_name
  tsv_file    = open(Dir.pwd + '/tsv_files/' + tsv_file_name)
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
  tsv_file = open(Dir.pwd + '/test_tsv/' + tsv_file_name)
  while (line = tsv_file.gets)
    next unless line.split(' ').last.include?("\/")
    id           = line.split(' ').last if line.split(' ').last.include?('10.')
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
  # chop in half and save two files with tsv_file_name   appended to end
  # return doi_file array appended with the new file name
  doi_path  = Dir.pwd + '/doi_files/' + doi_file[1] + '_part_1' + '.doi'
  doi_part_file  = File.new(doi_path, 'w') # create nt file - .tsv
  line_num = 0
  total_lines = File.open(doi_file[0]) {|f| f.count}
  last_line = ''
  # doi_file = File.open(doi_file[0])
  # while line_num < (total_lines / 2)
  #   doi_part_file.puts doi_file.gets
  #   last_line = doi_file.gets
  #   line_num.next
  # end
  puts '/**//*/*/*/* LAST LINE */*//*/**/*/*//*/**//**//*'
  puts last_line
  puts '/**//*/*/*/** LAST LINE /*//*/**/*/*//*/**//**//*'
# end of first part
  # while line_num < (doi_file[2] / 2)
  #   doi_part_file.puts tsv_file.gets
  #   line_num.next
  # end
  # while (line = tsv_file.gets)
  #   next unless line.split(' ').last.include?("\/")
  #   id = line.split(' ').last if line.split(' ').last.include?('10.')
  #   all_ids << id
  #   crossref_url = 'https://api.crossref.org/v1/works/http://dx.doi.org/'
  #   formed_url = crossref_url + id
  #   all_urls << formed_url
  # end
  doi_file << doi_part_file
  doi_file << 'part2.doi'
  puts '/**//*/*/*/**/*//*/**/*/*//*/**//**//*'
  puts 'chopping doi file in half'
  puts '/**//*/*/*/**/*//*/**/*/*//*/**//**//*'
  doi_file
end

def slice_random(doi_file) # :TODO change name
  # chop in half and save two files with tsv_file_name   appended to end
  # return doi_file array appended with the new file name
  doi_file << 'part1.doi'
  doi_file << 'part2.doi'
  doi_file << 'part3.doi'
  puts '/**//*/*/*/**/*//*/**/*/*//*/**//**//*'
  puts 'chopping doi file in three and saving '
  puts '/**//*/*/*/**/*//*/**/*/*//*/**//**//*'
  doi_file
end

def slice_doi_file(doi_file)
  if doi_file[2].even?
    doi_file = slice_in_half(doi_file)
  else
    doi_file =  slice_random(doi_file)
  end
  doi_file
end

def make_doi_nt(doi_file)
  doi_file[1] = doi_file[1].gsub('.tsv', '')
  nt_path  = Dir.pwd + '/nt_files/' + doi_file[1] + '.nt'
  nt_file  = File.new(nt_path, 'w') # create nt file - .tsv
  line_num = File.open(doi_file[0]) {|f| f.count}
  doi_file << line_num
  doi_file = slice_doi_file(doi_file)
  puts doi_file.inspect
  # doi_file = open(Dir.pwd + '/doi_file/' + doi_file)
  # log_file = File.new(Dir.pwd + '/log/' + Time.now.to_s + '.txt', 'w')
  # # log_file.puts '[START] [' + Time.now.to_s + '] started with ---> ' +
  #               # tsv_file_name
  # all_ids        = []
  # all_urls       = []
  # max_to_process = 25
  # puts '/**//*/**//**/*/*/*/*/*/*/*//**/*//*'
  #
  # # while (line = tsv_file.gets)
  # #   next unless line.split(' ').last.include?("\/")
  # #   id           = line.split(' ').last if line.split(' ').last.include?('10.')
  # #   crossref_url = 'https://api.crossref.org/v1/works/http://dx.doi.org/'
  # #   formed_url   = crossref_url + id
  # #   formed_url   = Addressable::URI.encode(formed_url.strip)
  # #   formed_url   = Addressable::URI.parse(formed_url)
  # #   formed_url   = URI(formed_url)
  # #   all_ids << id
  # #   all_urls << formed_url
  # #   next unless all_ids.size == max_to_process
  # #   make_connection(all_ids, all_urls, nt_file, log_file)
  # #   all_ids            = []
  # #   all_urls           = []
  # # end
  # # log_file.puts '[END] [' + Time.now.to_s + '] finished with ---> ' +
  # #               tsv_file_name
  # nt_file.close
  # log_file.close
  # doi_file.close
end

def make_connection(all_ids, all_urls, nt_file, log_file)
  crossref_uri = URI('https://api.crossref.org/v1/works/http://dx.doi.org/')
  crossref_url = 'https://api.crossref.org/v1/works/http://dx.doi.org/'
  property_url = 'http://purl.org/dc/terms/title'
  threads      = []
  Net::HTTP.start(crossref_uri.host, crossref_uri.port) do |_http|
    range = 0..all_ids.size - 1
    range.each do |num|
      id  = all_ids[num]
      url = all_urls[num]
      threads << Thread.new do
        puts '[INFO] processing ---> ' + id.to_s
        response = Net::HTTP.get_response(url)
        response = check_response(response, id, crossref_url, log_file)
        puts '[ERROR] resource not found ' unless response
        log_file.puts '[ERROR] resource not found ' + id.to_s unless response
        next unless response # skip to next in all_urls
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
  threads.each(&:join)
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
    recheck_id           = recheck_id.join('/')
    formed_url           = Addressable::URI.encode((c_url + recheck_id).strip)
    formed_url           = Addressable::URI.parse(formed_url)
    # formed_url = URI.parse(URI.encode(formed_url.strip))
    # puts '[INFO] re-trying again as --- ' + formed_url.to_s
    formed_url           = URI(formed_url)
    response             = Net::HTTP.get_response(formed_url)
    check_response(response, recheck_id, c_url, log_file) unless
    formed_url.to_s == c_url.to_s
  end
end
start
