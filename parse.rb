require 'active_support'
require 'active_support/core_ext'
require 'faraday'
require 'json'
require 'nokogiri'
require 'smarter_csv'

class Phone
  attr_reader :phone
  attr_accessor :current_provider, :previous_provider

  def initialize(phone)
    @phone = phone
  end

  def to_s
    "#{phone}: #{previous_provider == '' ? current_provider : "#{previous_provider} -> #{current_provider}"}"
  end
end

class Contact
  attr_reader :phones, :name

  def initialize(name, phones)
    @name = name
    @phones = phones
  end

  def to_s
    "#{name}: #{phones.map(&:to_s).join("\n")}"
  end
end

csv = SmarterCSV.process('contacts.csv')
contacts = csv.select! { |e| e[:name] }.map do |contact|
  keys = contact.keys.map(&:to_s).select { |key| key.match?(/^phone_(\d+)___value$/) }.map(&:to_sym)
  phones = keys.map { |k| contact[k].to_s }
  filtered_phones = phones.map { |phone| phone.split(':::') } # sometimes multiple phones presents at the same key
                          .flatten                            # merge results
                          .map { |e| e.scan(/\d/).join }      # remain only digits
                          .select { |e| e.start_with?('7') }  # remove non-russian phones
                          .map { |e| Phone.new(e.to_i) }      # create an object
  Contact.new(contact[:name], filtered_phones)
end

# removing contacts without valid phones
contacts.reject! { |contact| contact.phones.empty? }

contacts.sample(2).each_with_index do |contact, i|
  puts "(#{i + 1}/#{contacts.size}) Checking contact #{contact.name}..."
  contact.phones.each do |phone|
    puts "Checking phone #{phone.phone}..."
    result = Faraday.new(url: 'https://www.kody.su/check-tel').post { |req| req.body = "number=#{phone.phone}" }
    doc = Nokogiri::HTML(result.body)
    current_provider = doc.xpath("//p[contains(text(), 'Результат распознавания номера')]/following-sibling::p[span[2]]/span[2]").text
    previous_provider = doc.xpath('//s').text
    puts "\tCurrent: #{current_provider}"
    puts "\tPrevious: #{previous_provider}"
    phone.current_provider = current_provider
    phone.previous_provider = previous_provider
  end
end

File.open('result.json', 'w') { |file| file.write(contacts.to_json) }
