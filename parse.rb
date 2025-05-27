# frozen_string_literal: true

require "active_support/core_ext/hash/slice"
require 'active_support/json'
require 'faraday'
require 'json'
require 'nokogiri'
require 'smarter_csv'
require 'uri'

SUPPORTED_CONTACT_FIELDS = %i[first_name last_name middle_name phones]

Phone = Struct.new(:number, :current_provider, :previous_provider, keyword_init: true) do
  def to_s
    "#{number}: #{previous_provider == '' ? current_provider : "#{previous_provider} -> #{current_provider}"}"
  end
end

Contact = Struct.new(*SUPPORTED_CONTACT_FIELDS, keyword_init: true) do
  def to_s
    "#{first_name} #{last_name}: #{phones.map(&:to_s).join("\n")}"
  end
end

csv = SmarterCSV.process('contacts.csv')
contacts = csv&.select! { it.keys.map(&:to_s).any? { it.include?('name') } }
             &.map do |contact|
  phone_keys = contact.keys.map(&:to_s).select { |key| key.match?(/^phone_(\d+)___value$/) }.map(&:to_sym)

  filtered_phones = contact.slice(*phone_keys)
                           .values
                           .flat_map { it.to_s.split(':::') }  # sometimes multiple phones presents at the same key
                           .map { it.scan(/\d/).join }         # remain only digits
                           .select { it.start_with?('7') }     # remove non-russian phones
                           .map { Phone.new(number: it.to_i) } # create an object
  contact.merge!(phones: filtered_phones)
  contact.slice!(*SUPPORTED_CONTACT_FIELDS)
  Contact.new(contact)
end

# removing contacts without valid phones
contacts&.reject! { |contact| contact.phones.empty? }

contacts&.each_with_index do |contact, i|
  puts "(#{i + 1}/#{contacts&.size}) Checking contact #{contact.inspect}..."
  contact.phones.each do |phone|
    puts "Checking phone #{phone.number}..."
    result = Faraday.post('https://www.kody.su/check-tel') do |req|
      data = { number: phone.number }
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = URI.encode_www_form(data)
    end
    doc = Nokogiri::HTML(result.body)
    moved_to_operator = JSON.parse(Faraday.get("https://sp-app-proxyapi-08c.azurewebsites.net/api/mnp/#{phone.number}").body)['movedToOperator']
    initial_provider = doc.xpath("//p[text()='Результат распознавания номера:']/following-sibling::p//s").text
    initial_provider = doc.xpath("//p[text()='Результат распознавания номера:']/following-sibling::p[1]/span[2]").text if initial_provider.nil? || initial_provider.empty?
    puts "\tInitial: #{initial_provider}"
    puts "\tMoved To: #{moved_to_operator}"
    if moved_to_operator
      phone.current_provider = moved_to_operator
      phone.previous_provider = initial_provider
    else
      phone.current_provider = initial_provider
    end
  end
end

File.open('result.json', 'w') { |file| file.write(contacts.to_json) }
