# frozen_string_literal: true

SUPPORTED_CONTACT_FIELDS = %i[first_name last_name middle_name phones].freeze

Phone = Struct.new(:number, :region, :current_provider, :previous_provider, keyword_init: true)
Contact = Struct.new(*SUPPORTED_CONTACT_FIELDS, keyword_init: true)

desc "Parsing Google Contact's CSV file and get MNP information for all phones"
task :parse do
  require 'active_support/core_ext/hash/slice'
  require 'active_support/json'
  require 'http'
  require 'nokogiri'
  require 'smarter_csv'

  # @type [Array<Contact>]
  contacts = SmarterCSV::Reader.new('contacts.csv').process.then do |csv|
    csv.select { |entry| entry.keys.any? { |key| key.to_s.include?('name') } }
       .map do |contact|
      phone_keys = contact.keys.select { |key| key.to_s.match?(/^phone_(\d+)___value$/) }
      filtered_phones = contact.fetch_values(*phone_keys)
                               .flat_map   { it.to_s.split(':::') } # sometimes multiple phones presents at the same key
                               .map        { it.scan(/\d/).join }   # remain only digits in phone numbers
                               .filter_map { Phone.new(number: it.to_i) if it.start_with?('79') } # remove non-Russian phones and create an object
      contact.merge!(phones: filtered_phones)
      contact.slice!(*SUPPORTED_CONTACT_FIELDS)
      Contact.new(contact)
    end
  end

  contacts.select! { |contact| contact.phones.any? }

  contacts.each_with_index do |contact, index|
    puts "(#{index + 1}/#{contacts.size}) Checking contact #{contact.inspect}..."
    contact.phones.each do |phone|
      puts "Checking phone #{phone.number}..."
      raw_response = HTTP.post('https://www.kody.su/embed/widget.php', form: { number: phone.number })
                         .body.to_s
      if raw_response.downcase.include?('ошибка')
        puts raw_response
        next
      end

      response = Nokogiri::HTML::Document.parse(raw_response)
      region = response.xpath('//strong[contains(text(), "[") and contains(text(), "]")]')&.text&.scan(/\[.*?\]/)&.first&.[](1..-2)
      bdpn_result = response.xpath('//div[contains(@class, "result_bdpn")]').text
      initial_provider, moved_to_provider, region = if bdpn_result.downcase.include?('не перенесен')
                                                      [response.xpath('//td[contains(normalize-space(), "Код сотового оператора")]//strong').text.gsub(/\[.*?\],$/, '').strip,
                                                       nil,
                                                       region]
                                                    else
                                                      bdpn_result.gsub('БДПН: номер перенесен -', '').split('→').map(&:strip).push(region)
                                                    end
      puts "\tRegion: #{region}"
      puts "\tInitial: #{initial_provider}"
      puts "\tMoved To: #{moved_to_provider}"
      phone.region = region
      phone.previous_provider = initial_provider if moved_to_provider
      phone.current_provider = moved_to_provider || initial_provider
    end
  end

  File.open('result.json', 'w') { |file| file.write(JSON.pretty_generate(contacts.as_json)) }
end
