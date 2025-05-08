# spec/spec_helper.rb

RSpec.configure do |config|
  # デフォルトで標準出力に出力するように設定
  config.formatter = :documentation

  # テストの前にデータベースをリセットするなどの設定
  config.before(:each) do
    # テストデータのセットアップ
  end

  # テストの後処理
  config.after(:each) do
    # テスト後のクリーンアップ処理
  end

  # FactoryBotなどを自動的に利用する設定
  config.include FactoryBot::Syntax::Methods

  # 例外処理、カスタム設定など
  config.raise_errors_for_deprecations!
end
