require 'json'

class Hash
  def sort_desc_by_value
    sort_by { |_k, v| -v }.to_h
  end
end

class Array
  def values_count_by_key(key)
    each_with_object({}) { |val, sum| sum[val[key]] = sum[val[key]].to_i + 1 }.sort_desc_by_value
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
puts "Покидаемость (количество уходов от операторов): #{JSON.pretty_generate(mostly_abandoned_stat)}"
puts "Переходность (количество приходов к операторам): #{JSON.pretty_generate(transferred_phones_stat)}"

# {'название оператора, от которого уходят' -> [операторы, к которым ушли]}
abadoned_to_transfered_stat = transferred_phones.each_with_object({}) do |phone, hash|
  hash[phone['previous_provider']] ||= []
  hash[phone['previous_provider']] << phone['current_provider']
end
# а теперь считаем операторов, к которым ушли 
abadoned_to_transfered_stat.transform_values! do |value|
  value.each_with_object(Hash.new(0)) { |carrier, hash| hash[carrier] += 1 }.sort_desc_by_value
end
puts "Статистика, к кому и как часто уходят от операторов (от кого -> количество тех, к кому): #{JSON.pretty_generate(abadoned_to_transfered_stat)}"
