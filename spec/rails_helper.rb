# spec/rails_helper.rb
# RedmineのRails環境をロード
ENV['RAILS_ENV'] ||= 'development'

require File.expand_path('../../../../config/environment', __FILE__)
require_relative 'spec_helper'
require 'factory_bot_rails'

# RSpecの設定
RSpec.configure do |config|
  # テストの順序をランダム化
  config.order = :random

  # 必要に応じて他の設定を追加
end