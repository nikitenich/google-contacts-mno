# frozen_string_literal: true

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

desc 'Get statistics by MNP info'
task :stat do
  require 'ostruct'
  using StatisticsRefinements

  phones = File.read('result.json')
               .then { |file| JSON.parse(file, object_class: OpenStruct) }
               .flat_map(&:phones)

  puts "Статистика номеров по регионам: #{phones.values_count_by_key(:region)}"
  puts "Статистика операторов: #{phones.values_count_by_key(:current_provider)}"

  transferred_phones = phones.select(&:previous_provider)
  puts "Количество переходных номеров: #{transferred_phones.count}/#{phones.count}"
  puts "Покидаемость (количество уходов от операторов): #{transferred_phones.values_count_by_key(:previous_provider)}"
  puts "Переходность (количество приходов к операторам): #{transferred_phones.values_count_by_key(:current_provider)}"
  puts format('Статистика, к кому и как часто уходят от операторов (от кого -> количество тех, к кому): %s',
              transferred_phones.group_by(&:previous_provider)
                                .transform_values { it.map(&:current_provider).tally.sort_desc_by_value }
                                .to_s)
end
