# frozen_string_literal: true

module Helper
  # Defines one test per combination of parameter values for shared test modules.
  #
  # Topology comes from the suite that includes the module, so a generated test
  # skips itself when that suite's topology is not listed in `topologies`.
  module Parameterized
    private

    def parameterized_test(name, topologies: %i[standalone cluster], **parameters, &test_body)
      parameter_names = parameters.keys

      parameters.values.first.product(*parameters.values.drop(1)).each do |values|
        parameter_suffix = parameter_names.zip(values).map { |key, value| "#{key}_#{value}" }.join("_and_")

        define_method(:"#{name}_with_#{parameter_suffix}") do
          topology = cluster_mode? ? :cluster : :standalone
          skip "#{name} does not apply to #{topology}" unless topologies.include?(topology)

          instance_exec(*values, &test_body)
        end
      end
    end
  end
end
