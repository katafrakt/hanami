# frozen_string_literal: true

require "stringio"

RSpec.describe "Slices / Slice configuration", :app_integration do
  specify "Slices receive a copy of the app configuration, and can make distinct modifications" do
    with_tmp_directory(Dir.mktmpdir) do
      write "config/app.rb", <<~RUBY
        require "hanami"

        module TestApp
          class App < Hanami::App
            config.logger.stream = StringIO.new

            config.no_auto_register_paths = ["structs"]
          end
        end
      RUBY

      write "config/slices/main.rb", <<~'RUBY'
        module Main
          class Slice < Hanami::Slice
            config.no_auto_register_paths << "schemas"
          end
        end
      RUBY

      write "config/slices/search.rb", <<~'RUBY'
        module Search
          class Slice < Hanami::Slice
          end
        end
      RUBY

      require "hanami/prepare"

      expect(TestApp::App.config.no_auto_register_paths).to eq %w[structs]
      expect(Main::Slice.config.no_auto_register_paths).to eq %w[structs schemas]
      expect(Search::Slice.config.no_auto_register_paths).to eq %w[structs]
    end
  end

  specify "app config can include extra slices config for existing slices" do
    with_tmp_directory(Dir.mktmpdir) do
      write "lib/admin_slice/slice.rb", <<~'RUBY'
        module ExternalAdmin
          class Slice < Hanami::Slice
          end
        end
      RUBY

      write "config/app.rb", <<~RUBY
        require "hanami"
        require "admin_slice/slice"

        module TestApp
          class App < Hanami::App
            config.extra_slices = {
              extra_admin: ExternalAdmin::Slice
            }
          end
        end
      RUBY

      require "hanami/prepare"

      expect(TestApp::App.slices.keys).to include(:extra_admin)
      expect(TestApp::App.slices.to_a).to include(ExternalAdmin::Slice)

      # external slice should inherit config
      expect(ExternalAdmin::Slice.config.base_url.to_s).to eq("http://0.0.0.0:2300")
    end
  end
end
