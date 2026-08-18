# Redmine Project Importer

A Redmine plugin that allows you to import projects from other Redmine instances.

## Features

- Import projects unit by unit from another Redmine instance
- Migrate tickets including comments and custom fields  
- Preserve parent-child ticket relationships and version mappings
- Migrate wiki pages, including full content version history and same-project redirects

## Installation

1. Clone this repository to the `plugins` directory of your target Redmine installation.

    ```sh
    cd /var/lib/redmine/plugins
    git clone https://github.com/Mattani/redmine_project_importer.git
    ```

2. Install required gems if necessary.

    ```sh
    cd /var/lib/redmine
    bundle install
    ```

3. Restart Redmine.

## Quick Start

### Prerequisites

Before running the rake tasks, you need to load the source Redmine database into the `import_source` database area on the target Redmine server.

| Server | Type | Database | Description |
|--------|------|----------|-------------|
| Target Redmine Server | Target | redmine | Standard Redmine database |
|                       | Source | import_source | Database area referenced by this plugin |

### PostgreSQL Configuration

If PostgreSQL is configured for Redmine, you should have entries like this in `pg_hba.conf`:

```pg_hba.conf
host    redmine         redmine         127.0.0.1/32            md5
host    redmine         redmine         ::1/128                 md5
```

Add the following lines to allow the redmine user to access the `import_source` database:

```pg_hba.conf
host    redmine         redmine         127.0.0.1/32            md5
host    redmine         redmine         ::1/128                 md5
host    import_source   redmine         127.0.0.1/32            md5
host    import_source   redmine         ::1/128                 md5
```

### Plugin Configuration

Create `plugins/redmine_project_importer/config/database.yml` according to your environment.
Copy and edit `plugins/redmine_project_importer/config/database_sample.yml`.

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

### List Projects (Optional)

```sh
bundle exec rake redmine_project_importer:list_projects RAILS_ENV=production
```

### Pre-import

```sh
bundle exec rake redmine_project_importer:pre_import RAILS_ENV=production SOURCE_PROJECT_ID=1
```

This creates a YAML file: `redmine_project_importer.answer.(project_identifier).yml`

### Execute Import

```sh
bundle exec rake redmine_project_importer:exec_import RAILS_ENV=production SOURCE_PROJECT_ID=1
```

After execution, a result file will be created: `redmine_project_importer.result.(project_identifier).yml`

## Documentation

- [日本語ドキュメント (Japanese Documentation)](README.ja.md)
- [Detailed Installation Guide](docs/installation.md)
- [Configuration Guide](docs/configuration.md)
- [Usage Guide](docs/usage.md)
- [Troubleshooting](docs/troubleshooting.md)

## Requirements

- Redmine 5.0 or later
- Rails 6.1 or later (Required for Rails multi-database functionality)
- PostgreSQL

## License

MIT License

## Author

- H.Matsutani
- [GitHub](https://github.com/Mattani)
- [X (Twitter)](https://x.com/mattani)
