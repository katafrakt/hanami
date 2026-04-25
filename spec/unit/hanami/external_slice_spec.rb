# frozen_string_literal: true

require "hanami"
require "hanami/external_slice"
require "pathname"
require "tmpdir"

RSpec.describe Hanami::ExternalSlice, :app_integration do
  before do
    module TestApp
      class App < Hanami::App
      end
    end
  end

  describe "subclassing" do
    it "sets config.root to the directory of the subclassing file" do
      Dir.mktmpdir do |dir|
        slice_file = File.join(dir, "slice.rb")
        File.write(slice_file, <<~RUBY)
          require "hanami/external_slice"

          module FakeGem
            class Slice < Hanami::ExternalSlice
            end
          end
        RUBY

        load slice_file

        expect(FakeGem::Slice.config.root).to eq(Pathname(dir))
      ensure
        Object.send(:remove_const, :FakeGem) if defined?(FakeGem)
      end
    end

    it "lets the subclass body override config.root" do
      Dir.mktmpdir do |dir|
        slice_file = File.join(dir, "slice.rb")
        override_root = File.join(dir, "elsewhere")
        FileUtils.mkdir_p(override_root)

        File.write(slice_file, <<~RUBY)
          require "hanami/external_slice"

          module FakeGem
            class Slice < Hanami::ExternalSlice
              config.root = #{override_root.inspect}
            end
          end
        RUBY

        load slice_file

        expect(FakeGem::Slice.config.root).to eq(Pathname(override_root))
      ensure
        Object.send(:remove_const, :FakeGem) if defined?(FakeGem)
      end
    end

    it "produces a class that is itself a Hanami::Slice subclass" do
      expect(Hanami::ExternalSlice).to be < Hanami::Slice
    end
  end
end
