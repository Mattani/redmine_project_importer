require_relative '../../rails_helper'
require 'tmpdir'

RSpec.describe RedmineProjectImporter::ProjectImportService do
  let(:project_id) { 1 }
  let(:project_identifier) { 'test_project' }
  let(:source_project) do
    double(
      'SourceProject',
      id: project_id,
      name: 'Test Project',
      identifier: 'test_project',
      description: 'A sample project for testing.',
      is_public: true,
      created_on: Time.now,
      updated_on: Time.now,
      attributes: {
        'id' => project_id,
        'name' => 'Test Project',
        'description' => 'A sample project for testing.',
        'homepage' => "",
        'is_public' => true,
        'parent_id' => nil,
        'created_on' => Time.now,
        'updated_on' => Time.now,
        'identifier' => 'test_project',
        'lft' => 9,
        'rgt' => 10,
        'inherit_members' => false,
        'default_version_id' => nil,
        'default_assigned_to_id' => nil,
        'defalut_issue_query_id' => nil
      }
    )
  end
  let(:target_project) do
    double(
      'Project',
      id: 100,
      name: 'Test Project',
      identifier: 'test_project',
      description: 'A test project',
      is_public: true,
      created_on: Time.now,
      updated_on: Time.now,
      trackers: []
    )
  end
  let(:context_mgr) { instance_double(RedmineProjectImporter::ContextManager) }
  let(:answer_file_manager) { instance_double(RedmineProjectImporter::AnswerFileManager) }
  let(:file_path) { File.join(Dir.pwd, "redmine_project_importer.answer.test_project.yml").to_s }

  let(:mappings) do
    {
      groups_mapping: {
        10 => { group_name: "Group 10", target_group_id: 200, roles: [3] },
        15 => { group_name: "Group 15", target_group_id: 201, roles: [2, 4] }
      },
      members_mapping: {
        1 => { email_address: "user1@example.com", target_user_id: 101, roles: [1, 2] },
        2 => { email_address: "user2@example.com", target_user_id: 102, roles: [3] }
      },
      trackers_mapping: {
        2 => { target_tracker_id: 202, target_tracker_name: "Bug" },
        3 => { target_tracker_id: 203, target_tracker_name: "Feature" }
      },
      statuses_mapping: {
        3 => { target_status_id: 303, target_status_name: "In Progress" },
        4 => { target_status_id: 304, target_status_name: "Resolved" }
      },
      custom_fields_mapping: {
        4 => { custom_field_name: "Priority", target_id: 404 },
        5 => { custom_field_name: "Severity", target_id: 405 }
      }
    }
  end

  let(:answer_file_data) do
    {
      members_mapping: ['member1', 'member2'],
      statuses_mapping: ['status1'],
      trackers_mapping: ['tracker1'],
      custom_fields_mapping: ['customfield1']
    }
  end

  describe '.list_projects' do
    before do
      allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).and_yield
      allow(SourceProject).to receive(:order).with(:id).and_return([])
    end

    context 'when there are projects in the source database' do
      let(:source_projects) do
        [
          double('SourceProject', id: 1, name: 'Test Project')
        ]
      end

      before do
        allow(SourceProject).to receive(:order).with(:id).and_return(source_projects)
      end

      it 'logs the list of projects using RedmineProjectImporter.logger' do
        expect(RedmineProjectImporter.logger).to receive(:info).with("SOURCE_PROJECT_ID    : PROJECT_NAME")
        expect(RedmineProjectImporter.logger).to receive(:info).with("---------------------:--------------------------")
        expect(RedmineProjectImporter.logger).to receive(:info).with("SOURCE_PROJECT_ID=1  : Test Project")

        described_class.list_projects
      end
    end

    context 'when there are no projects in the source database' do
      before do
        allow(SourceProject).to receive(:order).with(:id).and_return([])
      end

      it 'logs that no projects were found using RedmineProjectImporter.logger' do
        expect(RedmineProjectImporter.logger).to receive(:info).with("No projects found.")

        described_class.list_projects
      end
    end
  end

  describe '.pre_import_project' do
    before do
      allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).and_yield
      allow(SourceProject).to receive(:find_by).with(id: project_id).and_return(source_project)
      allow(RedmineProjectImporter::ContextManager).to receive(:new).with(source_project).and_return(context_mgr)
      allow(RedmineProjectImporter::AnswerFileManager).to receive(:new).and_return(answer_file_manager)
      allow(context_mgr).to receive(:generate_mappings).and_return(mappings)
      allow(answer_file_manager).to receive(:create_answer_file).and_return(true)
      allow(context_mgr).to receive(:errors).and_return([]) # errorsのモックを追加
    end

    context 'when the project exists in the source database' do
      it 'logs the completion of the pre-import process' do
        log_messages = []
        allow(RedmineProjectImporter.logger).to receive(:info) do |message|
          log_messages << message
        end

        described_class.pre_import_project(project_id)

        expect(log_messages.last).to eq("Pre-import process completed successfully.")
      end
    end

    context 'when the project does not exist in the source database' do
      before do
        allow(SourceProject).to receive(:find_by).with(id: project_id).and_return(nil)
      end

      it 'logs a fatal message and exits the process' do
        expect { described_class.pre_import_project(project_id) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1) # exit(1)が呼び出されていることを確認
        end
      end
    end
  end

  describe '.import_project' do
    let(:output_dir) { Dir.mktmpdir }

    before do
      ENV['REDMINE_PROJECT_IMPORTER_USER_FILE_PATH'] = output_dir
      allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).and_yield
      allow(SourceProject).to receive(:find_by).with(id: project_id).and_return(source_project)
      allow(RedmineProjectImporter::ContextManager).to receive(:new).with(source_project).and_return(context_mgr)
      allow(context_mgr).to receive(:generate_mappings).and_return(mappings)
      allow(context_mgr).to receive(:mappings).and_return(mappings)
      allow(context_mgr).to receive(:clear_warnings)
      allow(context_mgr).to receive(:clear_errors)
      allow(context_mgr).to receive(:target_project=)
      allow(context_mgr).to receive(:source_project).and_return(source_project)
      allow(context_mgr).to receive(:target_project).and_return(target_project)
      allow(RedmineProjectImporter::AnswerFileManager).to receive(:new).and_return(answer_file_manager)
      allow(answer_file_manager).to receive(:load).and_return(mappings)
      allow(RedmineProjectImporter::MemberImportService).to receive(:import_members).and_return(true)
      allow(RedmineProjectImporter::IssueImportService).to receive(:import_issues).and_return(true)
      allow(RedmineProjectImporter::WikiImportService).to receive(:import_wiki).and_return(true)
      allow(context_mgr).to receive(:issue_id_map).and_return({ 1 => 101, 2 => 102 })
      allow(context_mgr).to receive(:version_id_map).and_return({})
      allow(context_mgr).to receive(:wiki_page_id_map).and_return({})
      allow(context_mgr).to receive(:store_summary).and_return(true)
      allow(context_mgr).to receive(:add_warning).and_return(true)
      allow(context_mgr).to receive(:warnings).and_return([])
      allow(context_mgr).to receive(:errors).and_return([])

      # headersメソッドをモックに追加
      allow(context_mgr).to receive(:headers).and_return({
        tool_version: '1.0.0'
      })

      # summaryメソッドをモックに追加
      allow(context_mgr).to receive(:summary).and_return({
        project_id: 100,
        project_identifier: 'test_project',
        project_name: 'Test Project',
        total_issues: 2,
        total_issues_in_db: 2,
        total_members: 2,
        total_members_in_db: 2,
        total_groups: 1,
        total_groups_in_db: 1,
        total_trackers: 2,
        total_trackers_in_db: 2,
        missing_member_emails: []
      })
    end

    after do
      ENV.delete('REDMINE_PROJECT_IMPORTER_USER_FILE_PATH')
      FileUtils.remove_entry(output_dir) if Dir.exist?(output_dir)
    end

    context 'when there are no errors' do
      it 'logs the result file creation message' do
        allow(Project).to receive(:new).and_return(target_project)
        allow(target_project).to receive(:save).and_return(true)

        log_messages = []
        allow(RedmineProjectImporter.logger).to receive(:info) do |message|
          log_messages << message
        end

        described_class.import_project(project_id)

        # 最後のログメッセージを評価
        expected_path = File.join(output_dir, "redmine_project_importer.result.test_project.yml")
        expect(log_messages.last).to eq("Result file created: #{expected_path}")
      end
    end
  end
end
