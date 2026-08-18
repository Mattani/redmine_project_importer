# Redmine Project Importer

他のRedmineインスタンスからプロジェクトをインポートできるRedmineプラグインです。

## 特長

- プロジェクト単位で別のRedmineからチケットをインポート
- チケットの追記情報、カスタムフィールドも移行
- 親子チケットのマッピング、バージョンの対応も維持
- Wikiページ（全バージョン履歴・同一プロジェクト内リダイレクトを含む）も同時に移行

## インストール

1. インポート先のRedmineの`plugins`ディレクトリにこのリポジトリをクローンします。

    ```sh
    cd /var/lib/redmine/plugins
    git clone https://github.com/Mattani/redmine_project_importer.git
    ```

2. 必要に応じて依存gemをインストールします。

    ```sh
    cd /var/lib/redmine
    bundle install
    ```

3. Redmineを再起動します。

## クイックスタート

### 前提条件

インポート先のRedmineサーバにインポート元のRedmineのDBを`import_source`データベース領域にロードしておきます。

| サーバ | 種別 | データベース | 説明 |
|--------|------|--------------|------|
| インポート先Redmineサーバ | ターゲット | redmine | 通常のRedmineのDB |
|                          | ソース | import_source | 本プラグインが参照するDB領域 |

### PostgreSQL設定

RedmineでPostgreSQLが設定されている場合、`pg_hba.conf`には以下のようなエントリがあるはずです：

```pg_hba.conf
host    redmine         redmine         127.0.0.1/32            md5
host    redmine         redmine         ::1/128                 md5
```

redmineユーザーが`import_source`データベースにアクセスできるよう、以下の行を追加します：

```pg_hba.conf
host    redmine         redmine         127.0.0.1/32            md5
host    redmine         redmine         ::1/128                 md5
host    import_source   redmine         127.0.0.1/32            md5
host    import_source   redmine         ::1/128                 md5
```

### プラグイン設定

`plugins/redmine_project_importer/config/database.yml`を環境に合わせて作成します。
`plugins/redmine_project_importer/config/database_sample.yml`をコピーして編集してください。

```yml
production:
  primary:
    adapter: postgresql
    database: redmine
    host: localhost
    username: redmine
    password: your_password
    encoding: utf8
    pool: 5
  import_source:
    adapter: postgresql
    database: import_source
    host: localhost
    username: redmine
    password: your_password
    encoding: utf8
    port: 5432
```

### プロジェクト一覧表示（任意）

```sh
bundle exec rake redmine_project_importer:list_projects RAILS_ENV=production
```

### インポート準備

```sh
bundle exec rake redmine_project_importer:pre_import RAILS_ENV=production SOURCE_PROJECT_ID=1
```

YAMLファイルが作成されます：`redmine_project_importer.answer.(project_identifier).yml`

### インポート実行

```sh
bundle exec rake redmine_project_importer:exec_import RAILS_ENV=production SOURCE_PROJECT_ID=1
```

実行後、結果ファイルが作成されます：`redmine_project_importer.result.(project_identifier).yml`

## ドキュメント

- [English Documentation](README.md)
- [詳細インストール手順](docs/installation.ja.md)
- [設定方法](docs/configuration.ja.md)
- [使い方](docs/usage.ja.md)
- [トラブルシューティング](docs/troubleshooting.ja.md)

## 動作環境

- Redmine 5.0以上
- Rails 6.1以上（Railsマルチデータベース機能が必要）
- PostgreSQL

## ライセンス

MIT License

## 作者

- H.Matsutani
- [GitHub](https://github.com/Mattani)
- [X (Twitter)](https://x.com/mattani)
