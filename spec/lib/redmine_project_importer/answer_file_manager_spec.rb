require_relative '../../rails_helper'
require_relative '../../../lib/redmine_project_importer/answer_file_manager'

require 'tmpdir'

RSpec.describe RedmineProjectImporter::AnswerFileManager do
  let(:project_id) { 1 }
  let(:project_identifier) { 'test_project' }
  let(:output_dir) { Dir.mktmpdir }
  let(:file_path) { File.join(output_dir, "redmine_project_importer.answer.#{project_identifier}.yml") }
  let(:context_mgr) { instance_double(RedmineProjectImporter::ContextManager, source_project: source_project) }
  let(:source_project) do
    double(
      'SourceProject',
      id: project_id,
      name: 'Test Project',
      identifier: 'test_project',
      description: 'A sample project for testing.',
      is_public: true,
      created_on: Time.now,
      updated_on: Time.now
    )
  end
  let(:manager) { described_class.new(context_mgr) }

  before do
    ENV['REDMINE_PROJECT_IMPORTER_USER_FILE_PATH'] = output_dir
    File.delete(manager.file_path) if File.exist?(manager.file_path)
    allow(context_mgr).to receive(:mappings).and_return(RedmineProjectImporter::ContextManager::DEFAULTS)
    allow(context_mgr).to receive(:headers).and_return({
      tool_version: '1.0.0'
    })

    # warnings と errors をデフォルトで空配列に設定
    allow(context_mgr).to receive(:warnings).and_return([]) 
    allow(context_mgr).to receive(:errors).and_return([]) 

    allow(context_mgr).to receive(:options).and_return({
      dry_run: true,
      skip_members: false
    })
  end

  after do
    ENV.delete('REDMINE_PROJECT_IMPORTER_USER_FILE_PATH')
    FileUtils.remove_entry(output_dir) if Dir.exist?(output_dir)
  end

  describe '#initialize' do
    it 'sets the correct file path based on the project identifier' do
      expected_path = File.join(output_dir, "redmine_project_importer.answer.test_project.yml")
      expect(manager.file_path).to eq(expected_path)
    end

    it 'initializes @data with DEFAULTS' do
      expect(manager.data).to eq(RedmineProjectImporter::ContextManager::DEFAULTS)
    end
  end

  describe '#create_answer_file' do
    it 'initializes the answer file with default values' do
      manager.create_answer_file

      # ファイルが生成されていることを確認
      expect(File.exist?(manager.file_path)).to be true

      # ファイルの内容を確認
      data = YAML.safe_load(File.read(manager.file_path), symbolize_names: true)

      # mappings の中身を確認
      expect(data[:mappings]).to eq({
        roles_mapping: {},
        groups_mapping: {},
        members_mapping: {},
        trackers_mapping: {},
        statuses_mapping: {},
        custom_fields_mapping: {}
      })

      # warnings と errors が存在しないことを確認
      expect(data).not_to have_key(:warnings)
      expect(data).not_to have_key(:errors)
    end

    it 'creates the answer file with generated mappings and headers' do
      # デフォルトではないデータをモック
      allow(context_mgr).to receive(:mappings).and_return({
        roles_mapping: {
          1 => { target_role_id: 501 }
        },
        groups_mapping: {
          10 => { group_name: "group10", target_group_id: 200, roles: [3] },
          15 => { group_name: "group15", target_group_id: 201, roles: [2, 4] }
        },
        members_mapping: {
          1 => { email_address: "user1@example.com", target_user_id: 101 },
          2 => { email_address: "user2@example.com", target_user_id: 102 }
        },
        trackers_mapping: {
          2 => { tracker_name: "Bug", target_tracker_id: 202 }
        },
        statuses_mapping: {
          3 => { status_name: "Open", target_status_id: 303 }
        },
        custom_fields_mapping: {
          4 => { custom_field_name: "Custom Field 1", target_id: 404 },
          5 => { custom_field_name: "Custom Field 2", target_id: 405 }
        }
      })

      manager.create_answer_file

      # ファイルの内容を確認
      data = YAML.safe_load(File.read(manager.file_path), symbolize_names: true)

      expect(data[:headers]).to eq({
        tool_version: '1.0.0'
      })

      expect(data[:mappings]).to eq({
        roles_mapping: {
          1 => { target_role_id: 501 }
        },
        groups_mapping: {
          10 => { group_name: "group10", target_group_id: 200, roles: [3] },
          15 => { group_name: "group15", target_group_id: 201, roles: [2, 4] }
        },
        members_mapping: {
          1 => { email_address: "user1@example.com", target_user_id: 101 },
          2 => { email_address: "user2@example.com", target_user_id: 102 }
        },
        trackers_mapping: {
          2 => { tracker_name: "Bug", target_tracker_id: 202 }
        },
        statuses_mapping: {
          3 => { status_name: "Open", target_status_id: 303 }
        },
        custom_fields_mapping: {
          4 => { custom_field_name: "Custom Field 1", target_id: 404 },
          5 => { custom_field_name: "Custom Field 2", target_id: 405 }
        }
      })
    end

    it 'includes warnings and errors in the generated file' do
      # warnings と errors をモックし直す
      allow(context_mgr).to receive(:warnings).and_return([
        "Warning 1: Something might be wrong.",
        "Warning 2: Check your configuration."
      ])
      allow(context_mgr).to receive(:errors).and_return([
        "Error 1: Something went wrong.",
        "Error 2: Unable to process data."
      ])

      manager.create_answer_file

      # ファイルの内容を確認
      data = YAML.safe_load(File.read(manager.file_path), symbolize_names: true)
      expect(data[:warnings]).to eq([
        {:"Warning 1"=>"Something might be wrong."},
        {:"Warning 2"=>"Check your configuration."}
      ])
      expect(data[:errors]).to eq([
        {:"Error 1"=>"Something went wrong."},
        {:"Error 2"=>"Unable to process data."}
      ])
    end

    it 'includes options in the generated file' do
      # options をモック
      allow(context_mgr).to receive(:options).and_return({
        dry_run: true,
        skip_members: false,
        additional_option: "test_value"
      })

      manager.create_answer_file

      # ファイルの内容を確認
      data = YAML.safe_load(File.read(manager.file_path), symbolize_names: true)

      # options の内容を検証
      expect(data[:options]).to eq({
        dry_run: true,
        skip_members: false,
        additional_option: "test_value"
      })
    end
  end

  describe '#load' do
    context 'when the answer file exists' do
      let(:file_content) do
        <<~YAML
          ---
          headers:
            tool_version: "1.0.0"
          mappings:
            groups_mapping:
              1:
                group_name: "Group A"
                target_group_id: 101
                roles: [1, 2]
            members_mapping:
              1:
                email_address: "user@example.com"
                target_user_id: 201
                roles: [3, 4]
            trackers_mapping: {}
            statuses_mapping: {}
            custom_fields_mapping: {}
        YAML
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'loads the answer file and stores data in context_mgr' do
        # デバッグ出力を追加
        allow(context_mgr).to receive(:store_data) do |data|
          puts "Actual data passed to store_data: #{data.inspect}"
        end

        manager.load

        expected_data = {
          headers: {
            tool_version: "1.0.0"
          },
          mappings: {
            groups_mapping: {
              1 => { group_name: "Group A", target_group_id: 101, roles: [1, 2] }
            },
            members_mapping: {
              1 => { email_address: "user@example.com", target_user_id: 201, roles: [3, 4] }
            },
            trackers_mapping: {},
            statuses_mapping: {},
            custom_fields_mapping: {}
          }
        }
        expect(context_mgr).to have_received(:store_data).with(expected_data)
      end
    end

    context 'when the answer file does not exist' do
      it 'raises an error' do
        allow(File).to receive(:exist?).with(file_path).and_return(false)

        expect { manager.load }.to raise_error("Answer file not found: #{file_path}")
      end
    end
  end
end
