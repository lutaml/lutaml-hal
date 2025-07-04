# frozen_string_literal: true

require_relative '../../spec_helper'

# CLASS LOADING ORDER ISSUE TESTS
# ================================
#
# These tests validate the lazy type resolution mechanism that solves the class loading
# order problem in lutaml-hal. This is a temporary solution until we can enforce
# autoload usage across all applications.
#
# WHAT THESE TESTS VALIDATE:
# - Consistent HAL type names regardless of file loading order
# - Performance of the lazy resolution mechanism
# - Backward compatibility with existing API
# - Graceful handling of non-existent classes
#
# FUTURE DEPRECATION:
# When autoload becomes standard practice, these tests can be removed along with
# the lazy resolution mechanism. The ideal future state would use direct class
# references with proper autoload setup.
#
# MIGRATION TIMELINE:
# 1. Current: Use lazy resolution (these tests)
# 2. Transition: Encourage autoload adoption
# 3. Future: Remove lazy resolution, require autoload
# 4. Cleanup: Remove these tests and the complex resolution code

RSpec.describe 'Class Loading Order Issue' do
  before(:each) do
    # Clean up any existing constants to ensure clean test state
    Object.send(:remove_const, :TestApp) if defined?(TestApp)
  end

  after(:each) do
    # Clean up constants after each test
    Object.send(:remove_const, :TestApp) if defined?(TestApp)
  end

  context 'when Page class is loaded before referenced class' do
    it 'should show consistent type names regardless of loading order' do
      # Define the test module structure
      module TestApp
        module Models
        end
      end

      # First, define a Page class that references another class via hal_link
      # This simulates loading the page before the referenced model
      module TestApp
        module Models
          class EcosystemPage < Lutaml::Hal::Page
            hal_link :groups, key: 'groups', realize_class: 'GroupIndex'
            hal_link :members, key: 'members', realize_class: 'AffiliationIndex'
          end
        end
      end

      # Now define the referenced classes (simulating late loading)
      module TestApp
        module Models
          class GroupIndex < Lutaml::Hal::Resource
          end
        end
      end

      module TestApp
        module Models
          class AffiliationIndex < Lutaml::Hal::Resource
          end
        end
      end

      # Create an instance with link data and serialize to HAL
      page = TestApp::Models::EcosystemPage.new(
        links: TestApp::Models::EcosystemPageLinkSet.new(
          groups: TestApp::Models::GroupIndexLink.new(href: '/groups'),
          members: TestApp::Models::AffiliationIndexLink.new(href: '/members')
        )
      )
      hal_data = JSON.parse(page.to_json)

      # Both types should show simple class names, not full namespaces
      # This is the desired behavior after the fix
      expect(hal_data['_links']['groups']['type']).to eq('GroupIndex')
      expect(hal_data['_links']['members']['type']).to eq('AffiliationIndex')

      # Before the fix, this test would fail because one or both would show
      # the full namespace like 'TestApp::Models::AffiliationIndex'
    end

    it 'demonstrates backward compatibility with realize_class parameter' do
      # This test ensures the old API still works
      module TestApp
        module Models
        end
      end

      # Use the legacy realize_class parameter
      module TestApp
        module Models
          class LegacyPage < Lutaml::Hal::Page
            hal_link :items, key: 'items', realize_class: 'ItemIndex'
          end
        end
      end

      module TestApp
        module Models
          class ItemIndex < Lutaml::Hal::Resource
          end
        end
      end

      page = TestApp::Models::LegacyPage.new(
        links: TestApp::Models::LegacyPageLinkSet.new(
          items: TestApp::Models::ItemIndexLink.new(href: '/items')
        )
      )
      hal_data = JSON.parse(page.to_json)

      # Should work the same way with lazy resolution
      expect(hal_data['_links']['items']['type']).to eq('ItemIndex')
    end
  end

  context 'when classes are loaded in different orders' do
    it 'should prefer simple class names when available' do
      # This test validates the fix implementation

      module TestApp
        module Models
        end
      end

      # Define classes in any order
      module TestApp
        module Models
          class GroupIndex < Lutaml::Hal::Resource
          end
        end
      end

      module TestApp
        module Models
          class EcosystemPage < Lutaml::Hal::Page
            hal_link :groups, key: 'groups', realize_class: 'GroupIndex'
            hal_link :members, key: 'members', realize_class: 'AffiliationIndex'
          end
        end
      end

      module TestApp
        module Models
          class AffiliationIndex < Lutaml::Hal::Resource
          end
        end
      end

      page = TestApp::Models::EcosystemPage.new(
        links: TestApp::Models::EcosystemPageLinkSet.new(
          groups: TestApp::Models::GroupIndexLink.new(href: '/groups'),
          members: TestApp::Models::AffiliationIndexLink.new(href: '/members')
        )
      )
      hal_data = JSON.parse(page.to_json)

      # After the fix, both should consistently show simple names
      expect(hal_data['_links']['groups']['type']).to eq('GroupIndex')
      expect(hal_data['_links']['members']['type']).to eq('AffiliationIndex')
    end

    it 'handles classes that do not exist gracefully' do
      module TestApp
        module Models
        end
      end

      module TestApp
        module Models
          class EcosystemPage < Lutaml::Hal::Page
            hal_link :nonexistent, key: 'nonexistent', realize_class: 'NonExistentClass'
          end
        end
      end

      page = TestApp::Models::EcosystemPage.new(
        links: TestApp::Models::EcosystemPageLinkSet.new(
          nonexistent: TestApp::Models::NonExistentClassLink.new(href: '/nonexistent')
        )
      )
      hal_data = JSON.parse(page.to_json)

      # Should return the original string when class doesn't exist
      expect(hal_data['_links']['nonexistent']['type']).to eq('NonExistentClass')
    end
  end

  context 'API parameter validation' do
    it 'requires realize_class parameter' do
      expect do
        Class.new(Lutaml::Hal::Resource) do
          hal_link :invalid, key: 'invalid'
        end
      end.to raise_error(ArgumentError)
    end

    it 'accepts both Class objects and strings for realize_class' do
      module TestApp
        module Models
        end
      end

      # Define the target class first
      module TestApp
        module Models
          class ItemIndex < Lutaml::Hal::Resource
          end
        end
      end

      # Test with Class object
      expect do
        Class.new(Lutaml::Hal::Page) do
          hal_link :items_class, key: 'items_class', realize_class: TestApp::Models::ItemIndex
        end
      end.not_to raise_error

      # Test with string
      expect do
        Class.new(Lutaml::Hal::Page) do
          hal_link :items_string, key: 'items_string', realize_class: 'ItemIndex'
        end
      end.not_to raise_error

      # Test with invalid type
      expect do
        Class.new(Lutaml::Hal::Page) do
          hal_link :items_invalid, key: 'items_invalid', realize_class: 123
        end
      end.to raise_error(ArgumentError, /realize_class must be a Class or String/)
    end

    it 'produces consistent output for both Class and string realize_class' do
      module TestApp
        module Models
        end
      end

      # Define the target class
      module TestApp
        module Models
          class ProductIndex < Lutaml::Hal::Resource
          end
        end
      end

      # Page using Class object
      module TestApp
        module Models
          class PageWithClass < Lutaml::Hal::Page
            hal_link :products, key: 'products', realize_class: TestApp::Models::ProductIndex
          end
        end
      end

      # Page using string
      module TestApp
        module Models
          class PageWithString < Lutaml::Hal::Page
            hal_link :products, key: 'products', realize_class: 'ProductIndex'
          end
        end
      end

      # Create instances and test output
      page_with_class = TestApp::Models::PageWithClass.new(
        links: TestApp::Models::PageWithClassLinkSet.new(
          products: TestApp::Models::ProductIndexLink.new(href: '/products')
        )
      )

      page_with_string = TestApp::Models::PageWithString.new(
        links: TestApp::Models::PageWithStringLinkSet.new(
          products: TestApp::Models::ProductIndexLink.new(href: '/products')
        )
      )

      hal_data_class = JSON.parse(page_with_class.to_json)
      hal_data_string = JSON.parse(page_with_string.to_json)

      # Both should produce the same type name
      expect(hal_data_class['_links']['products']['type']).to eq('ProductIndex')
      expect(hal_data_string['_links']['products']['type']).to eq('ProductIndex')
      expect(hal_data_class['_links']['products']['type']).to eq(hal_data_string['_links']['products']['type'])
    end
  end
end
