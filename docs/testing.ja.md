# テスト実行手順

## 前提

- `import_source`・`primary`（Redmine本体）それぞれのtest用DBが用意済みであること（`rake redmine_project_importer:setup_test_db` 等でセットアップ）
- `config/database.yml` の `test:` セクションが正しく設定されていること（`config/database_sample.yml` を参照）

## 実行コマンド

rspecは**必ずRedmineルートディレクトリ（`/var/lib/redmine`）から実行すること**。

```sh
cd /var/lib/redmine
RAILS_ENV=test bundle exec rspec plugins/redmine_project_importer/spec
```

特定のファイルのみ実行する場合:

```sh
cd /var/lib/redmine
RAILS_ENV=test bundle exec rspec plugins/redmine_project_importer/spec/lib/redmine_project_importer/database_connector_spec.rb
```

## なぜRedmineルートから実行する必要があるのか

このプラグインは独自の `Gemfile.lock`/`vendor/bundle` を持たない。プラグインの `Gemfile`（`rspec-rails`, `factory_bot_rails`, `faker` を宣言）は、Redmineルートの `Gemfile` が

```ruby
Dir.glob File.expand_path("../plugins/*/{Gemfile,PluginGemfile}", __FILE__) do |file|
  eval_gemfile file
end
```

によって自動的に読み込み・合流させる仕組みになっている。そのため、bundle関連コマンド（`bundle install`/`bundle exec` 等）はRedmineルートの `Gemfile`/`Gemfile.lock` を使う前提であり、プラグインディレクトリ単体で `bundle exec` しても依存gemが解決できず失敗する。

詳細な経緯は `develop/docs/design_log.md`（2026-08-07付の2エントリ）を参照。
