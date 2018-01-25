#!/usr/bin/env ruby

def start
  tsv_files = Dir.entries(Dir.pwd + '/tsv_files/') # list of files
  threads = []
  isbn_files = []
  puts '[START] started extracting all isbns to separate files '
  tsv_files.each do |tsv_file_name|
    next if (tsv_file_name == '.') || (tsv_file_name == '..') # skip these
    threads << Thread.new do
      puts '[INFO] extracting isbns from ' + tsv_file_name.to_s
      isbn_files << extract_isbn_to_file(tsv_file_name)
    end
  end
  threads.each(&:join)
  puts '[END] finished extracting all isbns to separate files '
  threads = []
  puts '[START] started composing n-triples from isbns '
  isbn_files.each do |isbn_file|
    threads << Thread.new do
      make_isbn_nt(isbn_file)
    end
  end
  threads.each(&:join)
  puts '[END] finished composing n-triples '
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

def extract_isbn_to_file(tsv_file_name)
  isbn_path  = Dir.pwd + '/isbn_files/' + tsv_file_name + '.isbn'
  isbn_file  = File.new(isbn_path.gsub('.tsv', ''), 'w') # create doi file
  tsv_file = open(Dir.pwd + '/tsv_files/' + tsv_file_name)
  while (line = tsv_file.gets)
    next unless line.split(' ').include?("isbn")
    id = line.split(' ').last if line.include?('isbn')
    isbn_file.puts id.strip if !id.nil?
  end
  isbn_file.close
  tsv_file.close
  to_return = []
  to_return << isbn_file
  to_return << tsv_file_name
  to_return
end

def slice_in_half_isbn(isbn_file)
  # slice in half and save two files with tsv_file_name
  # return isbn_file array appended with the new file name
  middle_section_line = if isbn_file[2].even?
                          isbn_file[2] / 2
                        else
                          (isbn_file[2] / 2).round
                        end
  part_num = isbn_file[3]
  part_id = '_part_'
  isbn_path = Dir.pwd + '/isbn_files/' + isbn_file[1] + part_id +
             (part_num + 1).to_s + '.isbn'
  isbn_part_file = File.new(isbn_path, 'w') # create isbn file - .tsv
  line_num = 0
  isbn_file_to_slice = File.open(isbn_file[0])
  while line_num < middle_section_line
    line = isbn_file_to_slice.gets
    isbn_part_file.puts line.strip if !line.nil?
    line_num += 1
  end
  isbn_file << isbn_part_file
  part_num += 1
  isbn_part_file.close # end of first part

  isbn_path = Dir.pwd + '/isbn_files/' + isbn_file[1] + part_id +
             (part_num + 1).to_s + '.isbn'
  isbn_part_file = File.new(isbn_path, 'w') # create isbn file - .tsv
  while line_num <= isbn_file[2]
    line = isbn_file_to_slice.gets
    isbn_part_file.puts line.strip if !line.nil?
    line_num += 1
  end
  isbn_file << isbn_part_file
  isbn_part_file.close # end of second part

  isbn_file_to_slice.close
  part_num += 1
  isbn_file[3] = part_num
  isbn_file
end

def make_isbn_nt(isbn_file)
  isbn_file[1] = isbn_file[1].gsub('.tsv', '')
  nt_path     = Dir.pwd + '/nt_files/' + isbn_file[1] + '.nt'
  nt_file     = File.new(nt_path, 'w') # create nt file - .tsv
  log_file    = File.new(Dir.pwd + '/log/' + Time.now.to_s + '.txt', 'w')
  line_num    = File.open(isbn_file[0], &:count)
  isbn_file << line_num
  isbn_file << 0 # parts counter "isbn_file[3]" no parts of this file
  isbn_file = slice_in_half_isbn(isbn_file)
  puts '[INFO] composing n-triples from isbns '
  isbn_part_files = []
  isbn_part_files << isbn_file[4]    # part 1
  isbn_part_files << isbn_file[5]    # part 2
  threads = []
  isbn_part_files.each do |isbn_part_file|
    range                = 1..25
    max_to_process       = 0
    isbn_part_file_lines  = File.open(isbn_part_file, &:count)
    range.each do |num|
      if (isbn_part_file_lines % num).zero?
        # max_to_process = num
        max_to_process = isbn_part_file_lines / num
      end
    end
    threads << Thread.new do
      all_ids        = []
      all_urls       = []
      isbn_part_file  = File.open(isbn_part_file)
      crossref_url   = 'http://api.crossref.org/types/book/works?filter=isbn:'
      while (id      = isbn_part_file.gets)
        formed_url = crossref_url + id
        formed_url = Addressable::URI.encode(formed_url.strip)
        formed_url = Addressable::URI.parse(formed_url)
        formed_url = URI(formed_url)
        all_ids << id
        all_urls << formed_url
        next unless all_ids.size == max_to_process # if equal pause and do >
        setup_process_isbn(all_ids, all_urls, nt_file, log_file)
        all_ids    = []
        all_urls   = []
      end
      isbn_part_file.close
    end
  end
  threads.each(&:join)
  log_file.puts '[END] [' + Time.now.to_s + '] finished with ---> '
  nt_file.close
  log_file.close
end

def setup_process_isbn(all_ids, all_urls, nt_file, log_file)
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
    execute_process_isbn(ids_to_process, urls_to_process, nt_file, log_file)
    ids_to_process = []
    urls_to_process = []
    while counter < all_ids.size - 1
      range = counter..(counter + 10)
      range.each do |num|
        ids_to_process << all_ids[num]
        urls_to_process << all_urls[num]
        counter += 1
      end
      execute_process_isbn(ids_to_process, urls_to_process, nt_file, log_file)
      ids_to_process = []
      urls_to_process = []
    end
  end
end

def execute_process_isbn(ids_to_process, urls_to_process, nt_file, log_file)
  threads = []
  crossref_uri = URI('http://api.crossref.org/types/book/works?filter=isbn:')
  # crossref_uri = URI('https://api.crossref.org/works/')
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
          items = json_response['message']['items']
          # titles = json_response['message']['title']
          if items.size > 0
            # title = items['title']
            items.each do |item|
              doi = item['DOI']
              title = item['title']
              n_triple = '<http://dx.doi.org/' + doi.strip + '>' + ' <' +
                         property_url + '> ' + title.inspect.to_s + '.'
              nt_file.puts n_triple
              # titles = item['title']
              # titles.each do |title|
              #   # nt_file.puts title.inspect.to_s
              #   n_triple = '<http://dx.doi.org/' + id.strip + '>' + ' <' +
              #              property_url + '> ' + title.inspect.to_s + '.'
              #   nt_file.puts n_triple
              # end
            end
            end
          end
        end
    end
    threads.each(&:join)
  end
end
start
