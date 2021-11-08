#
# Copyright 2021- Rémy DUTHU
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fluent/plugin/parser'
require 'nokogiri'

module Fluent
  module Plugin
    class XmlParser < Fluent::Plugin::Parser
      Fluent::Plugin.register_parser('xml', self)

      config_param :xpath, :hash
      config_param :xpath_types, :hash, default: nil
      config_param :time_format, :string, default: nil
      config_param :time_xpath, :array

      def configure(config)
        super

        # Create the time parser
        @time_parser = Fluent::TimeParser.new(@time_format)
      end

      def parse(text)
        begin
          # Open the XML document
          doc = Nokogiri.XML(text)

          # Create an empty record which assigns default values for missing
          # keys. See: https://stackoverflow.com/a/3339168.
          record = Hash.new { |h, k| h[k] = {} }

          # Create the time value
          time = @time_parser.parse(get_field_value(doc, @time_xpath))

          # Recursively parse XPath to handle nested structures
          deep_each_pair(@xpath) do |k, xpath, parents|
            # Retrieve the field value from the XPath
            value = get_field_value(doc, xpath)

            # Ignore the field if it has no value
            unless value.nil?
              # Convert the value
              type = @xpath_types.dig(*parents, k) unless @xpath_types.nil?
              value = convert(value, type) unless type.nil?

              # Save the field to the appropriate index (record["a"]["b"]["c"]).
              # See: https://stackoverflow.com/a/14294789.
              parents.inject(record, :[])[k] = value unless value.nil?
            end
          end

          yield(time, record)
        rescue StandardError
          yield(nil, nil)
        end
      end

      TRUTHY_VALUES = %w[true yes 1]

      # This function converts the value v into the type t based on:
      # https://github.com/fluent/fluentd/blob/5844f7209fec154a4e6807eb1bee6989d3f3297f/lib/fluent/plugin/parser.rb#L229.
      def convert(v, t)
        case t
        when 'bool'
          return TRUTHY_VALUES.include?(v.to_s.downcase)
        when 'float'
          return v.to_f
        when 'integer'
          return v.to_i
        when 'string'
          return v.to_s
        else
          return v
        end
      end

      def get_field_value(doc, xpath)
        begin
          elements = doc.xpath(xpath[0])
          throw if elements.nil?

          return elements.first[xpath[1]]
        rescue StandardError
          return
        end
      end

      def deep_each_pair(hash, parents = [])
        hash.each_pair do |k, v|
          if v.is_a?(Hash)
            parents << k

            deep_each_pair(v, parents) { |k, v, parents| yield(k, v, parents) }

            parents.pop
          elsif v.is_a?(Array) && v.size > 2
            attribute = v.last
            elements = v[0..-1]

            elements.each { |e| yield(k, [e, attribute], parents) }
          elsif v.is_a?(Array)
            yield(k, v, parents)
          end
        end
      end
    end
  end
end
