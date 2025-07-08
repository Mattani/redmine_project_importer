# Redmine Project Importer

Redmine Project Importerは、他のRedmineインスタンスからプロジェクトをインポートできるRedmineプラグインです。

## 特長

- プロジェクト単位でチケットを別のRedmineにコピーできます
- チケットおよびチケットの追記情報、カスタムフィールドも移行できます
- 親子チケットのマッピング、バージョンの対応も崩れずに移行できます

## インストール方法

1. このリポジトリをインポート先のRedmineの`plugins`ディレクトリに配置します。（以下、`/var/lib/redmine`にRedmineがインストールされている前提）

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

## 使い方

### 前提条件

本プラグインのrakeタスクを実行する前に、インポート先のRedmineサーバにインポート元のRedmineのDBをimport_source DB領域にロードしておきます。
PostgreSQLのDB領域として、以下のようになっていることが前提です。
（いずれもインポート先のRedmineサーバに設定します。インポート元のRedmineからはDBをExportしておくだけです。）

| サーバ                   | 種別         | DB領域名      | 備考                                         |
|--------------------------|--------------|--------------|----------------------------------------------|
| インポート先Redmineサーバ | インポート先  | redmine      | 通常のRedmineのDB領域                        |
|                          | インポート元  | import_source| 本プラグインが読み込み用に参照するDB領域      |

### プラグインの設定

`plugins/redmine_project_importer/config/database.yml`を環境にあわせて作成します。
`plugins/redmine_project_importer/config/database_sample.yml`ファイルをコピーして編集するのがおすすめです。
primaryセクションは、`/var/lib/redmine/config/database.yml`にあわせてください。
import_sourceセクションは、DB名以外は同じにすると簡単です。
プラグインを利用するだけであれば、productionセクションのみの設定で大丈夫です。

```yml:plugins/redmine_project_importer/config/database.yml
production:
  primary:
    adapter: postgresql
    database: redmine
    host: localhost
    username: redmine
    password: 環境にあわせて設定してください
    encoding: utf8
    pool: 5
  import_source:
    adapter: postgresql
    database: import_source
    host: localhost
    username: redmine
    password: 環境にあわせて設定してください
    encoding: utf8
    port: 5432
    variables:
      default_transaction_read_only: true
```

### インポート元のDBからプロジェクト一覧を表示

（インポートしたいプロジェクトのIDがわかっている場合はスキップ可能）

```sh
cd /var/lib/redmine/plugins
bundle exec rake redmine_project_importer:pre_import RAILS_ENV=production
```

（実行例）

```text
# bundle exec rake redmine_project_importer:pre_import RAILS_ENV=production
==================================================================
Redmine Project Importer plugin/0.1.1 Copyright(C)2025 H.Matsutani
        This software is released under the MIT License.
==================================================================
SOURCE_PROJECT_ID is not set. Please set it and try again.
SOURCE_PROJECT_ID    : PROJECT_NAME
---------------------:--------------------------
SOURCE_PROJECT_ID=1  : 開発プロジェクト
SOURCE_PROJECT_ID=2  : 新規事業立ち上げ
SOURCE_PROJECT_ID=3  : 社内改善タスク
```

### インポート準備(pre_importタスク)

pre_importタスクを実行して、インポート元のDBの指定したプロジェクトの関連情報を収集し、YAMLファイルに出力します。@redmine_project_importer.answer.（プロジェクト識別子）.yml@というファイルが出力されます。

```sh
bundle exec rake redmine_project_importer:pre_import RAILS_ENV=production SOURCE_PROJECT_ID=(プロジェクトID)
```

（実行例）

```text
# bundle exec rake redmine_project_importer:pre_import RAILS_ENV=production SOURCE_PROJECT_ID=1
==================================================================
Redmine Project Importer plugin/0.1.1 Copyright(C)2025 H.Matsutani
        This software is released under the MIT License.
==================================================================
Prepare importing project with ID: 1
  Project Import Service started. Source Project ID: 1
  Generating mappings for project ID: 1
    Generating custom field mappings
    Generating group mappings
      Warning: No matching target group found (source_group_id: 5, group_name: 開発G)
    Generating member mappings
    Generating tracker mappings
    Generating status mappings
Answer file created: /var/lib/redmine/redmine_project_importer.answer.development_project.yml
Pre-import process completed successfully.
```

## 対応バージョン

Redmine 5.0以上
（RailsのマルチDB機能を使用するため、Rails6.1以降となるRedmine5.0以上が必須です）

## ライセンス

MIT License

## 作者

- H.Matsutani  
- [GitHub](https://github.com/Mattani)  
- [X (旧Twitter)](https://x.com/mattani)
