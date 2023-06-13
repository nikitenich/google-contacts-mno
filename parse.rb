require 'active_support'
require 'active_support/core_ext'
require 'faraday'
require 'json'
require 'nokogiri'
require 'smarter_csv'
require 'uri'

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

contacts.each_with_index do |contact, i|
  puts "(#{i + 1}/#{contacts.size}) Checking contact #{contact.name}..."
  contact.phones.each do |phone|
    puts "Checking phone #{phone.phone}..."
    result = Faraday.post('https://www.spravportal.ru/Services/PhoneCodes/MobilePhoneInfo.aspx') do |req|
      data = { 'ctl00$ctl00$cphMain$cphServiceMain$textNumDesktop': phone.phone,
               '__VIEWSTATE': '/wEPDwUJMjM3NTc2NzA2ZBgBBS9jdGwwMCRjdGwwMCRjcGhNYWluJGNwaFNlcnZpY2VNYWluJG12QWRTZWxlY3Rvcg8PZAIBZDOasFzokPx73T/669/K11OOCyd1' }
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = URI.encode_www_form(data)
    end
    doc = Nokogiri::HTML(result.body)
    moved_to_operator = JSON.parse(Faraday.get("https://sp-app-proxyapi-08c.azurewebsites.net/api/mnp/#{phone.phone}").body)['movedToOperator']
    initial_provider = doc.xpath("//div[@class='form-group' and ./label[text()='Оператор']]//span").text
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
