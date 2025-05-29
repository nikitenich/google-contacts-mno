require 'json'

module StatisticsRefinements
  refine Hash do
    def sort_desc_by_value
      sort_by { |_key, value| -value }.to_h
    end

    def to_s
      JSON.pretty_generate(self)
    end
  end

  refine Array do
    def values_count_by_key(key)
      each_with_object({}) { |value, sum| sum[value[key]] = sum[value[key]].to_i + 1 }.sort_desc_by_value
    end

    def to_s
      JSON.pretty_generate(self)
    end
  end
end
using StatisticsRefinements

contacts = JSON.parse(File.read('result.json'), symbolize_names: true)
contacts_with_transfer = contacts.select { |contact| contact[:phones].any? { |phone| phone[:previous_provider] != nil } }
transferred_phones = contacts_with_transfer.flat_map { |contact| contact[:phones] }
transferred_phones_stat = transferred_phones.values_count_by_key(:current_provider)
mostly_abandoned_stat = transferred_phones.values_count_by_key(:previous_provider)

puts "Количество переходных номеров: #{transferred_phones.count}/#{contacts.flat_map { it[:phones] }.count}"
puts "Покидаемость (количество уходов от операторов): #{JSON.pretty_generate(mostly_abandoned_stat)}"
puts "Переходность (количество приходов к операторам): #{JSON.pretty_generate(transferred_phones_stat)}"

# {'название оператора, от которого уходят' -> [операторы, к которым ушли]}
abandoned_to_transferred_stat = transferred_phones.each_with_object({}) do |phone, hash|
  hash[phone[:previous_provider]] ||= []
  hash[phone[:previous_provider]] << phone[:current_provider]
end
# а теперь считаем операторов, к которым ушли 
abandoned_to_transferred_stat.transform_values! do |value|
  value.each_with_object(Hash.new(0)) { |carrier, hash| hash[carrier] += 1 }.sort_desc_by_value
end
puts "Статистика, к кому и как часто уходят от операторов (от кого -> количество тех, к кому): #{JSON.pretty_generate(abandoned_to_transferred_stat)}"
