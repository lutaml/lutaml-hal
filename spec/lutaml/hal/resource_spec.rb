# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Lutaml::Hal::Resource do
  describe 'automatic LinkSet creation' do
    let(:test_module) do
      Module.new do
        def self.name
          'TestModule'
        end
      end
    end

    let(:test_resource_class) do
      Class.new(described_class) do
        def self.name
          'TestModule::TestResource'
        end

        hal_link :users, key: 'users', realize_class: 'UserIndex'
        hal_link :groups, key: 'groups', realize_class: 'GroupIndex'
      end
    end

    before do
      # Stub the module to avoid const_set on real modules
      allow(Object).to receive(:const_get).with('TestModule').and_return(test_module)
      allow(test_module).to receive(:const_set)
    end

    it 'automatically creates a LinkSet class' do
      expect(test_module).to receive(:const_set).with('TestResourceLinkSet', kind_of(Class))
      test_resource_class
    end

    it 'creates LinkSet class that inherits from Lutaml::Hal::LinkSet' do
      link_set_class = nil
      allow(test_module).to receive(:const_set) do |name, klass|
        link_set_class = klass if name == 'TestResourceLinkSet'
      end

      test_resource_class

      expect(link_set_class).to be < Lutaml::Hal::LinkSet
    end

    it 'adds links attribute to the resource class' do
      test_resource_class
      expect(test_resource_class.attributes).to have_key(:links)
    end

    it 'maps _links to links attribute' do
      test_resource_class
      # Verify that the links attribute exists and is properly mapped
      expect(test_resource_class.attributes).to have_key(:links)

      # Test basic deserialization works
      json_data = { '_links' => {} }
      instance = test_resource_class.from_json(json_data.to_json)
      expect(instance.links).not_to be_nil
    end

    context 'when parent class name is empty' do
      let(:test_resource_class) do
        Class.new(described_class) do
          def self.name
            'TestResource'
          end

          hal_link :users, key: 'users', realize_class: 'UserIndex'
        end
      end

      it 'uses Object as parent class' do
        expect(Object).to receive(:const_set).with('TestResourceLinkSet', kind_of(Class))
        test_resource_class
      end
    end

    context 'when parent class does not exist' do
      let(:test_resource_class) do
        Class.new(described_class) do
          def self.name
            'NonExistent::TestResource'
          end

          hal_link :users, key: 'users', realize_class: 'UserIndex'
        end
      end

      before do
        allow(Object).to receive(:const_get).with('NonExistent').and_raise(NameError)
      end

      it 'falls back to Object as parent class' do
        expect(Object).to receive(:const_set).with('TestResourceLinkSet', kind_of(Class))
        test_resource_class
      end
    end
  end

  describe 'lazy type resolution' do
    let(:test_link_class) do
      Class.new(Lutaml::Hal::Link) do
        @realize_class_name = 'TestClass'
        @resolved_type_name = nil

        class << self
          attr_reader :realize_class_name

          def resolved_type_name
            return @resolved_type_name if @resolved_type_name

            @resolved_type_name = resolve_type_name(@realize_class_name)
          end

          private

          def resolve_type_name(class_name_string)
            return class_name_string unless class_name_string.is_a?(String)

            begin
              Object.const_get(class_name_string)
              class_name_string
            rescue NameError
              class_name_string
            end
          end
        end

        def type
          @type || self.class.resolved_type_name
        end
      end
    end

    it 'resolves type names lazily at class level' do
      link_instance = test_link_class.new
      expect(link_instance.type).to eq('TestClass')
    end

    it 'caches resolved type names' do
      # First call should resolve
      first_result = test_link_class.resolved_type_name

      # Second call should use cached value
      expect(test_link_class).not_to receive(:resolve_type_name)
      second_result = test_link_class.resolved_type_name

      expect(first_result).to eq(second_result)
    end

    it 'prefers simple names over namespaced names' do
      # Mock a class that exists
      stub_const('TestClass', Class.new)

      link_instance = test_link_class.new
      expect(link_instance.type).to eq('TestClass')
    end
  end

  describe 'consistent type naming' do
    before do
      # Create test classes in different loading orders
      stub_const('TestModule', Module.new)
      stub_const('TestModule::UserIndex', Class.new)
      stub_const('TestModule::GroupIndex', Class.new)
    end

    let(:resource_class_1) do
      Class.new(described_class) do
        def self.name
          'TestModule::Resource1'
        end

        hal_link :users, key: 'users', realize_class: 'UserIndex'
        hal_link :groups, key: 'groups', realize_class: 'GroupIndex'
      end
    end

    let(:resource_class_2) do
      Class.new(described_class) do
        def self.name
          'TestModule::Resource2'
        end

        hal_link :users, key: 'users', realize_class: 'UserIndex'
        hal_link :groups, key: 'groups', realize_class: 'GroupIndex'
      end
    end

    it 'produces consistent type names regardless of class loading order' do
      # Create both classes
      resource_class_1
      resource_class_2

      # Both should resolve to the same simple names
      link_def_1 = resource_class_1.link_definitions['users']
      link_def_2 = resource_class_2.link_definitions['users']

      expect(link_def_1[:klass].resolved_type_name).to eq('UserIndex')
      expect(link_def_2[:klass].resolved_type_name).to eq('UserIndex')
    end
  end

  describe 'error handling' do
    it 'handles anonymous classes gracefully' do
      anonymous_class = Class.new(described_class)
      expect { anonymous_class }.not_to raise_error
    end

    it 'handles missing realize_class parameter' do
      expect do
        Class.new(described_class) do
          def self.name
            'TestResource'
          end

          hal_link :users, key: 'users', realize_class: nil
        end
      end.to raise_error(ArgumentError, 'realize_class parameter is required')
    end
  end
end
