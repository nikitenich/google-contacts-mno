# frozen_string_literal: true

require 'active_support/core_ext/hash/slice'
require 'active_support/json'
require 'faraday'
require 'json'
require 'nokogiri'
require 'smarter_csv'
require 'uri'
require 'retriable'

SUPPORTED_CONTACT_FIELDS = %i[first_name last_name middle_name phones].freeze

Phone = Struct.new(:number, :region, :current_provider, :previous_provider, keyword_init: true)
Contact = Struct.new(*SUPPORTED_CONTACT_FIELDS, keyword_init: true)

KODY_SU_API = Faraday.new('https://www.kody.su/embed/widget.php') do |conn|
  conn.adapter :net_http do |http|
    http.open_timeout = 1
    http.read_timeout = 1
  end
  conn.headers['Content-Type'] = 'application/x-www-form-urlencoded' 
end

# @type [Array<Contact>]
contacts = SmarterCSV.process('contacts.csv').then do |csv|
  csv.select { |entry| entry.keys.map(&:to_s).any? { |key| key.include?('name') } }
     .map do |contact|
      phone_keys = contact.keys.map(&:to_s).select { it.match?(/^phone_(\d+)___value$/) }.map(&:to_sym)
      filtered_phones = contact.fetch_values(*phone_keys)
                               .flat_map { it.to_s.split(':::') }       # sometimes multiple phones presents at the same key
                               .map      { it.scan(/\d/).join }         # remain only digits
                               .select   { it.start_with?('79') }       # remove non-Russian phones
                               .map      { Phone.new(number: it.to_i) } # create an object
      contact.merge!(phones: filtered_phones)
      contact.slice!(*SUPPORTED_CONTACT_FIELDS)
      Contact.new(contact)
    end
end

# removing contacts without valid phones
contacts.reject! { |contact| contact.phones.empty? }

contacts.each_with_index do |contact, index|
  puts "(#{index + 1}/#{contacts.size}) Checking contact #{contact.inspect}..."
  contact.phones.each do |phone|
    puts "Checking phone #{phone.number}..."
    response = Retriable.retriable(tries: 5, base_interval: 1, on: Faraday::ConnectionFailed) do
      KODY_SU_API.post { |req| req.body = URI.encode_www_form({ number: phone.number }) }
                 .body
                 .then(&Nokogiri::HTML.method(:parse))
    end
    region = response.xpath('//strong[contains(text(), "[") and contains(text(), "]")]')&.text&.scan(/\[.*?\]/)&.first[1..-2]
    bdpn_result = response.xpath('//div[contains(@class, "result_bdpn")]').text
    initial_provider, moved_to_provider, region = if bdpn_result.downcase.include?('не перенесен')
                                                    [response.xpath('//div[@class="result_row"]/span[preceding-sibling::img]').text, nil, region]
                                                  else
                                                    bdpn_result.gsub('БДПН: номер перенесен -', '').split('→').map(&:strip).push(region)
                                                  end
    puts "\tRegion: #{region}"
    puts "\tInitial: #{initial_provider}"
    puts "\tMoved To: #{moved_to_provider}"
    phone.region = region
    if moved_to_provider
      phone.current_provider = moved_to_provider
      phone.previous_provider = initial_provider
    else
      phone.current_provider = initial_provider
    end
  end
end

File.open('result.json', 'w') { |file| file.write(contacts.to_json) }
