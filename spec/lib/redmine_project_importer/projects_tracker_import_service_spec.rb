require_relative '../../rails_helper'

RSpec.describe RedmineProjectImporter::ProjectsTrackerImportService do
  let(:source_project) { double('SourceProject', id: 1, name: 'Source Project') }
  let(:target_project) { double('TargetProject', id: 2, name: 'Target Project', trackers: target_trackers) }
  let(:context_mgr) do
    instance_double(
      'RedmineProjectImporter::ContextManager',
      source_project: source_project,
      target_project: target_project,
      mappings: { trackers_mapping: trackers_mapping }
    )
  end
  let(:trackers_mapping) do
    {
      1 => { target_tracker_id: 101, target_tracker_name: 'Bug' },
      2 => { target_tracker_id: 102, target_tracker_name: 'Feature' }
    }
  end
  let(:target_trackers) { double('TrackersAssociation', pluck: existing_tracker_ids, delete: nil) }

  before do
    allow(target_trackers).to receive(:<<)
    allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).and_yield
    allow(Tracker).to receive(:where).with(id: 101).and_return([double('Tracker', id: 101, name: 'Bug')])
    allow(Tracker).to receive(:where).with(id: 102).and_return([double('Tracker', id: 102, name: 'Feature')])
    allow(Tracker).to receive(:where).with(id: 999).and_return([])
  end

  describe '.import_trackers' do
    context 'when adding missing trackers' do
      let(:existing_tracker_ids) { [101] } # 追加対象のみ

      it 'adds missing trackers to the target project' do
        expect(target_trackers).to receive(:<<).with(anything).once
        described_class.import_trackers(context_mgr)
      end
    end

    context 'when removing unnecessary trackers' do
      let(:existing_tracker_ids) { [101, 999] } # 削除対象を含む

      it 'removes unnecessary trackers from the target project' do
        allow(Tracker).to receive(:where).with(id: 999).and_return([double('Tracker', id: 999, name: 'Obsolete')])
        expect(target_trackers).to receive(:delete).with(instance_of(RSpec::Mocks::Double)).once
        described_class.import_trackers(context_mgr)
      end
    end

    context 'when a tracker is not found in the database' do
      let(:existing_tracker_ids) { [101] } # 削除対象なし

      it 'logs a fatal error if a tracker is not found in the database' do
        allow(trackers_mapping).to receive(:values).and_return([{ target_tracker_id: 999, target_tracker_name: 'Nonexistent' }])
        allow(Tracker).to receive(:where).with(id: 999).and_return([])

        # logger.fatal の呼び出しをモック
        allow(RedmineProjectImporter.logger).to receive(:fatal)

        described_class.import_trackers(context_mgr)

        # logger.fatal が正しいメッセージで呼び出されたことを検証
        expect(RedmineProjectImporter.logger).to have_received(:fatal).with('Tracker with ID 999 not found in the database')
      end
    end
  end
end
