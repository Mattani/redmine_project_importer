require_relative '../../rails_helper'

RSpec.describe RedmineProjectImporter::JournalImportService do
  describe '.import_journals' do
    let(:issue_id_map) { { 1 => 101, 2 => 102, 3 => 103 } }
    let(:answer_file_data) do
      {
        members_mapping: {
          1 => { email_address: 'user1@example.com', target_user_id: 201, roles: [1, 2] },
          2 => { email_address: 'user2@example.com', target_user_id: 202, roles: [3] }
        }
      }
    end
    let(:source_journals) do
      [
        double('SourceJournal', id: 1, journalized_id: 1, user_id: 1, notes: 'Test note', created_on: Time.now),
        double('SourceJournal', id: 2, journalized_id: 2, user_id: 2, notes: 'Another note', created_on: Time.now),
        double('SourceJournal', id: 3, journalized_id: 3, user_id: 3, notes: 'No mapping', created_on: Time.now)
      ]
    end
    let(:context_mgr) { double('ContextManager') } # モックの作成
    let(:mappings) do
      {
        members_mapping: {
          1 => { email_address: 'user1@example.com', target_user_id: 201, roles: [1, 2] },
          2 => { email_address: 'user2@example.com', target_user_id: 202, roles: [3] }
        }
      }
    end
    let(:target_project) { double('TargetProject', id: 1, name: 'Test Project') } # target_projectのモック

    before do
      allow(RedmineProjectImporter::JournalImportService).to receive(:fetch_source_journals)
        .and_return(source_journals.select { |j| issue_id_map.key?(j.journalized_id) })

      allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).and_yield
      allow(User).to receive_message_chain(:anonymous, :id).and_return(4)

      # `context_mgr`のメソッドをモック
      allow(context_mgr).to receive(:add_warning)
      allow(context_mgr).to receive(:add_error)
      allow(context_mgr).to receive(:target_project).and_return(target_project) # target_projectのモックを使用
      allow(context_mgr).to receive(:issue_id_map).and_return(issue_id_map) # issue_id_mapのモック
      allow(context_mgr).to receive(:mappings).and_return(mappings) # mappingsのモック

      puts "Fetched journals: #{source_journals.inspect}"
      puts "Anonymous user id: #{User.anonymous.id}"
    end

    it 'creates journals with correct user_id' do
      expect(Journal).to receive(:create!).with(
        hash_including(journalized_id: 101, user_id: 201, notes: 'Test note')
      )
      expect(Journal).to receive(:create!).with(
        hash_including(journalized_id: 102, user_id: 202, notes: 'Another note')
      )
      expect(Journal).to receive(:create!).with(
        hash_including(journalized_id: 103, user_id: 4, notes: 'No mapping')
      )

      RedmineProjectImporter::JournalImportService.import_journals(context_mgr)
    end

    it 'adds a warning (not an error) when Journal.create! raises a validation error' do
      invalid_journal = Journal.new
      invalid_journal.valid?
      allow(Journal).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(invalid_journal))

      RedmineProjectImporter::JournalImportService.import_journals(context_mgr)

      expect(context_mgr).to have_received(:add_warning).with(
        hash_including(message: a_string_including('Failed to copy journal #1: Validation error'))
      ).at_least(:once)
      expect(context_mgr).not_to have_received(:add_error)
    end

    it 'adds a warning (not an error) when Journal.create! raises an unexpected error' do
      allow(Journal).to receive(:create!).and_raise(StandardError, 'boom')

      RedmineProjectImporter::JournalImportService.import_journals(context_mgr)

      expect(context_mgr).to have_received(:add_warning).with(
        hash_including(message: a_string_including('Failed to copy journal #1: Unexpected error'))
      ).at_least(:once)
      expect(context_mgr).not_to have_received(:add_error)
    end
  end
end
