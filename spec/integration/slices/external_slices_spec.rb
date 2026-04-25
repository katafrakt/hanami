# frozen_string_literal: true

require "rack/test"
require "stringio"

RSpec.describe "Slices / External slices", :app_integration, :aggregate_failures do
  include Rack::Test::Methods

  let(:app_modules) { %i[TestApp Admin Main Search Sysinfo] }

  describe "basic loading" do
    it "loads a slice listed in config.external_slices" do
      with_tmp_directory(Dir.mktmpdir) do
        write "config/app.rb", <<~'RUBY'
          require "hanami"

          module TestApp
            class App < Hanami::App
              config.logger.stream = StringIO.new
              config.external_slices = [:sysinfo]
            end
          end
        RUBY

        write "lib/sysinfo.rb", <<~'RUBY'
          require "sysinfo/slice"

          module Sysinfo
          end
        RUBY

        write "lib/sysinfo/slice.rb", <<~'RUBY'
          require "hanami/external_slice"

          module Sysinfo
            class Slice < Hanami::ExternalSlice
            end
          end
        RUBY

        require "hanami/prepare"

        expect(Hanami.app.slices.keys).to include(:sysinfo)
        expect(Hanami.app.slices[:sysinfo]).to be Sysinfo::Slice
        expect(Hanami.app.slices[:sysinfo].config.root).to eq(Pathname(Dir.pwd).join("lib/sysinfo"))
      end
    end
  end

  describe "autoloading" do
    it "autoloads actions/ from the slice root" do
      with_tmp_directory(Dir.mktmpdir) do
        write "config/app.rb", <<~'RUBY'
          require "hanami"

          module TestApp
            class App < Hanami::App
              config.logger.stream = StringIO.new
              config.external_slices = [:sysinfo]
            end
          end
        RUBY

        write "lib/sysinfo.rb", <<~'RUBY'
          require "sysinfo/slice"

          module Sysinfo
          end
        RUBY

        write "lib/sysinfo/slice.rb", <<~'RUBY'
          require "hanami/external_slice"

          module Sysinfo
            class Slice < Hanami::ExternalSlice
            end
          end
        RUBY

        write "lib/sysinfo/actions/ping.rb", <<~'RUBY'
          require "hanami/action"

          module Sysinfo
            module Actions
              class Ping < Hanami::Action
                def handle(_req, res)
                  res.body = "pong"
                end
              end
            end
          end
        RUBY

        require "hanami/prepare"

        action = Hanami.app.slices[:sysinfo]["actions.ping"]
        expect(action).to be_a(Sysinfo::Actions::Ping)
      end
    end
  end

  describe "filtering via config.slices" do
    it "skips an external slice that is not in config.slices" do
      with_tmp_directory(Dir.mktmpdir) do
        write "config/app.rb", <<~'RUBY'
          require "hanami"

          module TestApp
            class App < Hanami::App
              config.logger.stream = StringIO.new
              config.slices = ["main"]
              config.external_slices = [:sysinfo]
            end
          end
        RUBY

        write "slices/main/.keep"

        write "lib/sysinfo.rb", <<~'RUBY'
          require "sysinfo/slice"

          module Sysinfo
          end
        RUBY

        write "lib/sysinfo/slice.rb", <<~'RUBY'
          require "hanami/external_slice"

          module Sysinfo
            class Slice < Hanami::ExternalSlice
            end
          end
        RUBY

        require "hanami/prepare"

        expect(Hanami.app.slices.keys).to eq([:main])
      end
    end
  end

  describe "mounting in routes" do
    it "serves requests through a mounted external slice" do
      with_tmp_directory(Dir.mktmpdir) do
        write "config/app.rb", <<~'RUBY'
          require "hanami"

          module TestApp
            class App < Hanami::App
              config.logger.stream = StringIO.new
              config.assets.serve = false
              config.external_slices = [:sysinfo]
            end
          end
        RUBY

        write "config/routes.rb", <<~'RUBY'
          require "hanami/routes"

          module TestApp
            class Routes < Hanami::Routes
              slice :sysinfo, at: "/sysinfo" do
                root to: "ping"
              end
            end
          end
        RUBY

        write "lib/sysinfo.rb", <<~'RUBY'
          require "sysinfo/slice"

          module Sysinfo
          end
        RUBY

        write "lib/sysinfo/slice.rb", <<~'RUBY'
          require "hanami/external_slice"

          module Sysinfo
            class Slice < Hanami::ExternalSlice
            end
          end
        RUBY

        write "lib/sysinfo/actions/ping.rb", <<~'RUBY'
          require "hanami/action"

          module Sysinfo
            module Actions
              class Ping < Hanami::Action
                def handle(_req, res)
                  res.body = "pong"
                end
              end
            end
          end
        RUBY

        require "hanami/prepare"

        def app = Hanami.app

        get "/sysinfo"

        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq("pong")
      end
    end
  end

  describe "error handling" do
    it "raises SliceLoadError with a gem-install hint when the gem is missing" do
      with_tmp_directory(Dir.mktmpdir) do
        write "config/app.rb", <<~'RUBY'
          require "hanami"

          module TestApp
            class App < Hanami::App
              config.logger.stream = StringIO.new
              config.external_slices = [:does_not_exist]
            end
          end
        RUBY

        expect { require "hanami/prepare" }.to raise_error(
          Hanami::SliceLoadError,
          /external slice 'does_not_exist' could not be required.*is the gem in your Gemfile/
        )
      end
    end

    it "raises SliceLoadError when the gem does not define <Module>::Slice" do
      with_tmp_directory(Dir.mktmpdir) do
        write "config/app.rb", <<~'RUBY'
          require "hanami"

          module TestApp
            class App < Hanami::App
              config.logger.stream = StringIO.new
              config.external_slices = [:sysinfo]
            end
          end
        RUBY

        # Gem requires cleanly, but does not define Sysinfo::Slice
        write "lib/sysinfo.rb", <<~'RUBY'
          module Sysinfo
          end
        RUBY

        expect { require "hanami/prepare" }.to raise_error(
          Hanami::SliceLoadError,
          /external slice 'sysinfo' was required but Sysinfo::Slice is not defined/
        )
      end
    end

    it "raises SliceLoadError when a name is declared both locally and externally" do
      with_tmp_directory(Dir.mktmpdir) do
        write "config/app.rb", <<~'RUBY'
          require "hanami"

          module TestApp
            class App < Hanami::App
              config.logger.stream = StringIO.new
              config.external_slices = [:sysinfo]
            end
          end
        RUBY

        # Local slice with the same name
        write "slices/sysinfo/.keep"

        write "lib/sysinfo.rb", <<~'RUBY'
          require "sysinfo/slice"

          module Sysinfo
          end
        RUBY

        write "lib/sysinfo/slice.rb", <<~'RUBY'
          require "hanami/external_slice"

          module Sysinfo
            class Slice < Hanami::ExternalSlice
            end
          end
        RUBY

        expect { require "hanami/prepare" }.to raise_error(
          Hanami::SliceLoadError,
          /declared both locally.*and as external/
        )
      end
    end
  end

  describe "config.root override" do
    it "lets the subclass body set config.root, overriding the inferred default" do
      with_tmp_directory(Dir.mktmpdir) do
        write "config/app.rb", <<~'RUBY'
          require "hanami"

          module TestApp
            class App < Hanami::App
              config.logger.stream = StringIO.new
              config.external_slices = [:sysinfo]
            end
          end
        RUBY

        write "lib/sysinfo.rb", <<~'RUBY'
          require "sysinfo/slice"

          module Sysinfo
          end
        RUBY

        # Subclass body sets config.root explicitly; the body runs after the
        # ExternalSlice.inherited hook, so the body's value wins.
        write "lib/sysinfo/slice.rb", <<~'RUBY'
          require "hanami/external_slice"
          require "pathname"

          module Sysinfo
            class Slice < Hanami::ExternalSlice
              config.root = Pathname(__dir__).join("..")
            end
          end
        RUBY

        require "hanami/prepare"

        expect(Hanami.app.slices[:sysinfo].config.root)
          .to eq(Pathname(Dir.pwd).join("lib/sysinfo/..").expand_path)
      end
    end
  end
end
