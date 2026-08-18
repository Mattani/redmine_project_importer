require_relative '../../rails_helper'
require_relative '../../../lib/redmine_project_importer/wiki_import_service'

RSpec.describe RedmineProjectImporter::WikiImportService, type: :service do
  let(:source_project) { double('Project', id: 1, name: 'Source Project') }
  let(:target_project) { double('Project', id: 100, name: 'Target Project') }
  let(:mappings) do
    {
      members_mapping: {
        1 => { email_address: 'user1@example.com', target_user_id: 101, roles: [1, 2] }
      }
    }
  end
  let(:context_mgr) { double('ContextManager') }
  let(:wiki_page_id_map) { {} }

  before do
    allow(context_mgr).to receive(:add_warning)
    allow(context_mgr).to receive(:add_error)
    allow(context_mgr).to receive(:source_project).and_return(source_project)
    allow(context_mgr).to receive(:target_project).and_return(target_project)
    allow(context_mgr).to receive(:mappings).and_return(mappings)
    allow(context_mgr).to receive(:wiki_page_id_map).and_return(wiki_page_id_map)

    allow(User).to receive(:anonymous).and_return(double(id: 4))
    allow(User).to receive(:exists?).and_return(true)

    allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).and_yield
  end

  describe '.import_wiki' do
    context 'when the source project has no wiki' do
      before do
        allow(described_class).to receive(:fetch_source_wiki).with(source_project.id).and_return(nil)
      end

      it 'does nothing and does not raise' do
        expect(Wiki).not_to receive(:new)
        described_class.import_wiki(context_mgr)
      end
    end

    context 'when the source project has a wiki' do
      let(:source_wiki) { double('SourceWiki', id: 10, project_id: 1, start_page: 'Wiki', status: 1) }
      let(:mock_wiki) { double('Wiki', id: 200, save!: true) }

      let(:source_page_parent) do
        double('SourceWikiPage', id: 20, wiki_id: 10, title: 'Parent', created_on: Time.now,
          protected: false, parent_id: nil)
      end
      let(:source_page_child) do
        double('SourceWikiPage', id: 21, wiki_id: 10, title: 'Child', created_on: Time.now,
          protected: true, parent_id: 20)
      end
      let(:mock_page_parent) { double('WikiPage', id: 300, save!: true) }
      let(:mock_page_child) { double('WikiPage', id: 301, save!: true, update!: true) }

      before do
        allow(described_class).to receive(:fetch_source_wiki).with(source_project.id).and_return(source_wiki)
        allow(Wiki).to receive(:find_by).and_return(nil)
        allow(Wiki).to receive(:new).and_return(mock_wiki)
        allow(described_class).to receive(:fetch_source_wiki_pages).with(source_wiki.id)
          .and_return([source_page_parent, source_page_child])
        allow(WikiPage).to receive(:new).and_return(mock_page_parent, mock_page_child)
        allow(WikiPage).to receive(:find).with(301).and_return(mock_page_child)
        allow(described_class).to receive(:fetch_wiki_contents_by_page).and_return({})
        allow(described_class).to receive(:fetch_source_wiki_redirects).with(source_wiki.id).and_return([])
      end

      it 'creates a new Wiki for the target project' do
        described_class.import_wiki(context_mgr)

        expect(Wiki).to have_received(:new).with(
          hash_including(project_id: target_project.id, start_page: 'Wiki', status: 1)
        )
      end

      context 'when the target project already has a wiki (e.g. auto-created by Redmine when the wiki module is enabled)' do
        let(:existing_wiki) { double('Wiki', id: 999, start_page: 'Old', status: 1, update!: true) }

        before do
          allow(Wiki).to receive(:find_by).with(project_id: target_project.id).and_return(existing_wiki)
        end

        it 'reuses the existing wiki instead of creating a new one' do
          described_class.import_wiki(context_mgr)

          expect(Wiki).not_to have_received(:new)
          expect(existing_wiki).to have_received(:update!).with(start_page: 'Wiki', status: 1)
        end

        it 'creates wiki pages under the reused wiki' do
          described_class.import_wiki(context_mgr)

          expect(WikiPage).to have_received(:new).with(
            hash_including(wiki_id: existing_wiki.id, title: 'Parent')
          )
          expect(WikiPage).to have_received(:new).with(
            hash_including(wiki_id: existing_wiki.id, title: 'Child')
          )
        end
      end

      it 'creates WikiPages for every source page' do
        described_class.import_wiki(context_mgr)

        expect(WikiPage).to have_received(:new).with(
          hash_including(wiki_id: mock_wiki.id, title: 'Parent', protected: false)
        )
        expect(WikiPage).to have_received(:new).with(
          hash_including(wiki_id: mock_wiki.id, title: 'Child', protected: true)
        )
      end

      it 'resolves parent_id using the wiki_page_id_map after all pages are created' do
        described_class.import_wiki(context_mgr)

        expect(wiki_page_id_map).to eq({ 20 => 300, 21 => 301 })
        expect(mock_page_child).to have_received(:update!).with(parent_id: 300)
      end

      context 'when the parent page mapping is missing' do
        let(:source_page_child) do
          double('SourceWikiPage', id: 21, wiki_id: 10, title: 'Child', created_on: Time.now,
            protected: false, parent_id: 999)
        end

        it 'skips the relation without raising' do
          expect { described_class.import_wiki(context_mgr) }.not_to raise_error
          expect(mock_page_child).not_to have_received(:update!)
        end
      end
    end
  end

  describe '.import_wiki (contents)' do
    let(:source_wiki) { double('SourceWiki', id: 10, project_id: 1, start_page: 'Wiki', status: 1) }
    let(:mock_wiki) { double('Wiki', id: 200, save!: true) }
    let(:source_page) do
      double('SourceWikiPage', id: 20, wiki_id: 10, title: 'Page', created_on: Time.now,
        protected: false, parent_id: nil)
    end
    let(:mock_page) { double('WikiPage', id: 300, save!: true) }

    let(:source_content) do
      double('SourceWikiContent', id: 40, page_id: 20, author_id: 1, text: 'latest text',
        comments: 'latest', updated_on: Time.now, version: 2)
    end
    let(:source_version_1) do
      double('SourceWikiContentVersion', id: 50, wiki_content_id: 40, page_id: 20, author_id: 1,
        data: 'v1'.b, compression: '', comments: 'v1', updated_on: Time.now, version: 1)
    end
    let(:source_version_2) do
      double('SourceWikiContentVersion', id: 51, wiki_content_id: 40, page_id: 20, author_id: 999,
        data: 'v2'.b, compression: '', comments: 'v2', updated_on: Time.now, version: 2)
    end

    before do
      allow(described_class).to receive(:fetch_source_wiki).with(source_project.id).and_return(source_wiki)
      allow(Wiki).to receive(:find_by).and_return(nil)
      allow(Wiki).to receive(:new).and_return(mock_wiki)
      allow(described_class).to receive(:fetch_source_wiki_pages).with(source_wiki.id).and_return([source_page])
      allow(WikiPage).to receive(:new).and_return(mock_page)
      allow(described_class).to receive(:fetch_source_wiki_redirects).with(source_wiki.id).and_return([])

      allow(described_class).to receive(:fetch_wiki_contents_by_page).and_return(
        { 20 => { content: source_content, versions: [source_version_1, source_version_2] } }
      )
      allow(described_class).to receive(:insert_wiki_content).and_return(400)
      allow(described_class).to receive(:insert_wiki_content_version)
    end

    it 'inserts the latest wiki content with the mapped author_id' do
      described_class.import_wiki(context_mgr)

      expect(described_class).to have_received(:insert_wiki_content).with(300, 101, source_content)
    end

    it 'inserts every historical version with the mapped author_id' do
      described_class.import_wiki(context_mgr)

      expect(described_class).to have_received(:insert_wiki_content_version).with(400, 300, 101, source_version_1)
    end

    it 'falls back to Anonymous and warns when a version author is not mapped' do
      described_class.import_wiki(context_mgr)

      expect(described_class).to have_received(:insert_wiki_content_version).with(400, 300, 4, source_version_2)
      expect(context_mgr).to have_received(:add_warning).with(
        hash_including(source_author_id: 999, source_page_id: 20)
      )
    end

    context 'when insert_wiki_content fails to return an id' do
      before do
        allow(described_class).to receive(:insert_wiki_content).and_return(nil)
      end

      it 'skips inserting versions for that page' do
        described_class.import_wiki(context_mgr)

        expect(described_class).not_to have_received(:insert_wiki_content_version)
      end
    end
  end

  describe '.import_wiki (redirects)' do
    let(:source_wiki) { double('SourceWiki', id: 10, project_id: 1, start_page: 'Wiki', status: 1) }
    let(:mock_wiki) { double('Wiki', id: 200, save!: true) }

    let(:same_project_redirect) do
      double('SourceWikiRedirect', id: 60, wiki_id: 10, title: 'Old Title',
        redirects_to: 'New Title', created_on: Time.now, redirects_to_wiki_id: 10)
    end
    let(:cross_project_redirect) do
      double('SourceWikiRedirect', id: 61, wiki_id: 10, title: 'Moved Page',
        redirects_to: 'Elsewhere', created_on: Time.now, redirects_to_wiki_id: 999)
    end
    let(:mock_redirect) { double('WikiRedirect', id: 700, save!: true) }

    before do
      allow(described_class).to receive(:fetch_source_wiki).with(source_project.id).and_return(source_wiki)
      allow(Wiki).to receive(:find_by).and_return(nil)
      allow(Wiki).to receive(:new).and_return(mock_wiki)
      allow(described_class).to receive(:fetch_source_wiki_pages).with(source_wiki.id).and_return([])
      allow(described_class).to receive(:fetch_wiki_contents_by_page).and_return({})
      allow(described_class).to receive(:fetch_source_wiki_redirects).with(source_wiki.id)
        .and_return([same_project_redirect, cross_project_redirect])
      allow(WikiRedirect).to receive(:new).and_return(mock_redirect)
    end

    it 'copies redirects that stay within the same project' do
      described_class.import_wiki(context_mgr)

      expect(WikiRedirect).to have_received(:new).with(
        hash_including(wiki_id: mock_wiki.id, title: 'Old Title', redirects_to: 'New Title',
          redirects_to_wiki_id: mock_wiki.id)
      )
    end

    it 'skips redirects pointing to another project and records a warning' do
      described_class.import_wiki(context_mgr)

      expect(WikiRedirect).not_to have_received(:new).with(hash_including(title: 'Moved Page'))
      expect(context_mgr).to have_received(:add_warning).with(
        hash_including(source_redirect_title: 'Moved Page', message: a_string_including('999'))
      )
    end
  end
end
