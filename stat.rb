require 'json'

class Array
  def values_count_by_key(key)
    result = each_with_object({}) do |val, sum|
      sum[val[key]] = sum[val[key]].to_i + 1
    end
    result.sort_by { |k, v| -v }.to_h
  end
end

contacts = JSON.parse(File.read('result.json'))
contacts_with_transfer = contacts.select do |contact|
  contact['phones'].any? do |phone|
    phone.key?('previous_provider')
  end
end
transferred_phones = contacts_with_transfer.map { |contact| contact['phones'] }.flatten
transferred_phones_stat = transferred_phones.values_count_by_key('current_provider')
mostly_abandoned_stat = transferred_phones.values_count_by_key('previous_provider')

puts "Количество переходных номеров: #{transferred_phones.count}/#{contacts.map { |c| c['phones'] }.flatten.count}"
puts "Покидаемость (количество уходов от операторов): #{mostly_abandoned_stat}"
puts "Переходность (количество приходов к операторам): #{transferred_phones_stat}"
