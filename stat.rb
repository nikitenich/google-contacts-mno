# frozen_string_literal: true

require 'ostruct'

module StatisticsRefinements # rubocop:disable Style/Documentation
  require 'json'
  require 'active_support/core_ext/enumerable'

  refine Hash do
    def sort_desc_by_value = sort_by { |_key, value| -value }.to_h

    def to_s = JSON.pretty_generate(self)
  end

  refine Array do
    # @param [Object] key
    # @return [Hash{Object -> Integer}]
    def values_count_by_key(key) = pluck(key).tally.sort_desc_by_value

    def to_s = JSON.pretty_generate(self)
  end
end
using StatisticsRefinements

phones = JSON.parse(File.read('result.json'), object_class: OpenStruct)
             .flat_map(&:phones)
puts "Статистика номеров по регионам: #{phones.values_count_by_key(:region)}"
puts "Статистика операторов: #{phones.values_count_by_key(:current_provider)}"

transferred_phones = phones.select(&:previous_provider)
transferred_phones_stat = transferred_phones.values_count_by_key(:current_provider)
mostly_abandoned_stat = transferred_phones.values_count_by_key(:previous_provider)
puts "Количество переходных номеров: #{transferred_phones.count}/#{phones.count}"
puts "Покидаемость (количество уходов от операторов): #{mostly_abandoned_stat}"
puts "Переходность (количество приходов к операторам): #{transferred_phones_stat}"

abandoned_to_transferred_stat = transferred_phones.each_with_object({}) do |phone, hash|
  previous_provider_name = phone.previous_provider
  hash[previous_provider_name] ||= []
  hash[previous_provider_name] << phone.current_provider
end.transform_values { |migrated_to_providers| migrated_to_providers.tally.sort_desc_by_value }

puts "Статистика, к кому и как часто уходят от операторов (от кого -> количество тех, к кому): #{abandoned_to_transferred_stat}"
