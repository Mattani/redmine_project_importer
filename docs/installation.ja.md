# インストールガイド

このドキュメントでは、Redmine Project Importerプラグインの詳細なインストール手順を説明します。

## 前提条件

### システム要件

- Redmine 5.0以上
- Rails 6.1以上（Railsマルチデータベース機能が必要）
- PostgreSQL
- Ruby 3.0以上（推奨）

### データベース構成

インポート先のRedmineサーバに以下の2つのデータベースが必要です：

| データベース名 | 用途 | 説明 |
|----------------|------|------|
| `redmine` | ターゲット | インポート先の通常のRedmineデータベース |
| `import_source` | ソース | インポート元Redmineのデータベース（コピー） |

## データベースの準備

### 1. import_sourceデータベースの作成

PostgreSQLで新しいデータベースを作成します：

```sql
-- PostgreSQLにスーパーユーザーで接続
sudo -u postgres psql

-- import_sourceデータベースを作成
CREATE DATABASE import_source OWNER redmine;

-- 権限を確認
\l
```

### 2. インポート元データのコピー

インポート元RedmineのデータベースダンプをPostgreSQLにインポートします：

```bash
# インポート元Redmineサーバでダンプを作成
pg_dump -h source_host -U source_user source_redmine_db > source_redmine_dump.sql

# インポート先サーバにコピー
scp source_redmine_dump.sql target_server:/tmp/

# インポート先サーバでimport_sourceデータベースにインポート
psql -h localhost -U redmine -d import_source < /tmp/source_redmine_dump.sql
```

### 3. PostgreSQL設定の更新

#### pg_hba.confの編集

PostgreSQLの設定ファイル `pg_hba.conf` を編集して、redmineユーザーが両方のデータベースにアクセスできるようにします：

```bash
# PostgreSQL設定ファイルの場所を確認
sudo -u postgres psql -c "SHOW config_file;"

# pg_hba.confファイルを編集
sudo vi /etc/postgresql/14/main/pg_hba.conf
```

**変更前：**

```pg_hba.conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD
host    redmine         redmine         127.0.0.1/32            md5
host    redmine         redmine         ::1/128                 md5
```

**変更後：**

```pg_hba.conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD
host    redmine         redmine         127.0.0.1/32            md5
host    redmine         redmine         ::1/128                 md5
host    import_source   redmine         127.0.0.1/32            md5
host    import_source   redmine         ::1/128                 md5
```

#### PostgreSQLサービスの再起動

```bash
sudo systemctl restart postgresql
```

#### 接続テスト

設定が正しく行われたかテストします：

```bash
# redmineデータベースへの接続テスト
psql -h localhost -U redmine -d redmine -c "SELECT version();"

# import_sourceデータベースへの接続テスト
psql -h localhost -U redmine -d import_source -c "SELECT version();"
```

## プラグインのインストール

### 1. プラグインファイルの配置

```bash
# Redmineのpluginsディレクトリに移動
cd /var/lib/redmine/plugins

# GitHubからプラグインをクローン
git clone https://github.com/Mattani/redmine_project_importer.git

# ファイル権限の設定
chown -R redmine:redmine redmine_project_importer
```

### 2. 依存関係のインストール

```bash
# Redmineのルートディレクトリに移動
cd /var/lib/redmine

# bundlerで依存gemをインストール
bundle install

# プラグインの依存関係も確認
bundle exec rake redmine:plugins RAILS_ENV=production
```

## プラグイン設定

### 1. データベース設定ファイルの作成

```bash
# 設定ディレクトリに移動
cd /var/lib/redmine/plugins/redmine_project_importer/config

# サンプル設定ファイルをコピー
cp database_sample.yml database.yml

# 設定ファイルを編集
vi database.yml
```

### 2. database.ymlの設定例

```yaml
production:
  primary:
    adapter: postgresql
    database: redmine
    host: localhost
    username: redmine
    password: your_redmine_password
    encoding: utf8
    pool: 5
    port: 5432

  import_source:
    adapter: postgresql
    database: import_source
    host: localhost
    username: redmine
    password: your_redmine_password
    encoding: utf8
    port: 5432

development:
  primary:
    adapter: postgresql
    database: redmine_development
    host: localhost
    username: redmine
    password: your_redmine_password
    encoding: utf8
    pool: 5

  import_source:
    adapter: postgresql
    database: import_source_development
    host: localhost
    username: redmine
    password: your_redmine_password
    encoding: utf8
```

### 3. ファイル権限の設定

```bash
# 設定ファイルの権限を適切に設定（セキュリティのため）
chmod 600 database.yml
chown redmine:redmine database.yml
```

## Redmineの再起動

### Apacheサービスの再起動

```bash
sudo systemctl restart httpd
```

### インストール確認

```bash
# Redmineのログを確認
tail -f /var/lib/redmine/log/production.log

# プラグインが正しく読み込まれているか確認
bundle exec rake redmine:plugins RAILS_ENV=production
```

出力例：

```text
Redmine plugins:
  redmine_project_importer    1.0.0
```

## 動作確認

### プロジェクト一覧の表示

```bash
cd /var/lib/redmine
bundle exec rake redmine_project_importer:list_projects RAILS_ENV=production
```

成功した場合の出力例：

```text
SOURCE_PROJECT_ID    : PROJECT_NAME
---------------------:--------------------------
SOURCE_PROJECT_ID=1  : Test Project
SOURCE_PROJECT_ID=2  : Development Project
```

エラーが発生した場合は、[トラブルシューティング](troubleshooting.ja.md)を参照してください。

## 次のステップ

インストールが完了したら、以下のドキュメントを参照してください：

- [設定方法](configuration.ja.md) - 詳細な設定オプション
- [使い方](usage.ja.md) - 実際のインポート手順
- [トラブルシューティング](troubleshooting.ja.md) - 問題解決ガイド
