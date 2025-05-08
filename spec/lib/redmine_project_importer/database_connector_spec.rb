# spec/lib/redmine_project_importer/database_connector_spec.rb
require_relative '../../rails_helper'
require_relative '../../../lib/redmine_project_importer/database_connector'

RSpec.describe RedmineProjectImporter::DatabaseConnector do
  let(:import_config_path) { File.expand_path('../../../config/database.yml', __dir__) }

  it 'establishes and uses a connection to the import_source DB' do
    expect {
      RedmineProjectImporter::DatabaseConnector.with_connection(
        env: 'test',
        config_path: import_config_path,
        namespace: :import_source
      ) do
        current_db = ActiveRecord::Base.connection.current_database
        expect(current_db).to eq('import_source_test')
      end
    }.not_to raise_error
  end
end
