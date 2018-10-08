require_relative "../test_helper"
require 'newrelic/elasticsearch'
require 'newrelic/elasticsearch/operation_resolver'
require 'webmock/minitest'

NewRelic::Agent.require_test_helper
DependencyDetection.detect!

class NewRelic::ElasticsearchTest < Minitest::Unit::TestCase
  def setup
    stub_request(:any, /.*?localhost:9200.*/)
    stub_request(:any, /.*?169.254.169.254.*/) # this is the AWS instance identity check - we don't care about this in test
    stub_request(:any, /.*?metadata.google.internal.*/) # google cloud instance identity check
    stub_request(:any, /.*?collector.newrelic.com.*/) # check in with new relic
    NewRelic::Agent.manual_start
    @client = Elasticsearch::Client.new(url: 'http://localhost:9200')
  end

  def test_instruments_search
    with_config(notice_nosql_statement: true) do
      in_transaction do
        @client.search(index: 'test', body: { query: { match_all: {}} })
      end
    end

    assert_metrics_recorded('Datastore/operation/Elasticsearch/Search')
    assert_metrics_recorded('Datastore/statement/Elasticsearch/Test/Search')
  end

  def test_instruments_update_with_scope
    with_config(notice_nosql_statement: true) do
      in_transaction do
        @client.update({index: 'searchable-listings-production', type: 'test', id: 1, retry_on_conflict: 5, body: { doc: {meat_popicle: true, meat: 'beef'}, doc_as_upsert: true } })
      end
    end

    assert_metrics_recorded('Datastore/operation/Elasticsearch/Update')
    assert_metrics_recorded('Datastore/statement/Elasticsearch/SearchableListings/Update')
  end

  def test_client_info
    with_config(notice_nosql_statement: true) do
      in_transaction do
        @client.info
      end
    end

    assert_metrics_recorded('Datastore/operation/Elasticsearch/ServerGet')
  end
end

class NewRelic::ElasticsearchOperationResolverTest < Minitest::Unit::TestCase
  # see the list in endpoint_list.txt for a list of elasticsearch endpoints
  # that you can instrument - if you want to add another endpoint (or remove it
  # from the instrumentation, you can reload a different file for the list
  # of resolvable operaions
  #

  def test_operation_nam
    resolver = NewRelic::ElasticsearchOperationResolver.new('POST', '/test/_aliases')
    assert_equal('IndicesAliases', resolver.operation_name)
  end

  def test_path_components
    resolver = NewRelic::ElasticsearchOperationResolver.new('POST', '/test/test/_warmer/warm')
    assert_equal(['test','test','_warmer','warm'], resolver.path_components)
  end

  def test_path_components_with_special_characters
    resolver = NewRelic::ElasticsearchOperationResolver.new('POST', '/test%2A/test/_warmer/warm')
    assert_equal(['test*','test','_warmer','warm'], resolver.path_components)
  end

  def test_operands
    resolver = NewRelic::ElasticsearchOperationResolver.new('GET', '/test/_alias/test-alias')
    assert_equal(['test-alias'], resolver.operands)
  end

  def test_api_name
    resolver = NewRelic::ElasticsearchOperationResolver.new('GET', '/test/things/_search_shards')
    assert_equal('_search_shards', resolver.api_name)
  end

  def test_scope
    resolver = NewRelic::ElasticsearchOperationResolver.new('GET', '/test/things/1')
    assert_equal(['test', 'things', '1'], resolver.scope)
  end

  def test_index
    resolver = NewRelic::ElasticsearchOperationResolver.new('GET', '/test/things/1')
    assert_equal('Test', resolver.index)
    assert_equal('Things', resolver.type)
  end

  def test_scope_path
    resolver = NewRelic::ElasticsearchOperationResolver.new('GET', '/test/things/1')
    assert_equal('test_things_1' , resolver.scope_path)
  end

  def test_ambiguous_method_resolver
    resolver = NewRelic::ElasticsearchOperationResolver.new('GET', '/test/things/1')
    assert_equal('DocumentGet', resolver.operation_name)

    resolver = NewRelic::ElasticsearchOperationResolver.new('PUT', '/test/things')
    assert_equal('TypeCreate', resolver.operation_name)

    resolver = NewRelic::ElasticsearchOperationResolver.new('HEAD', '/test')
    assert_equal('IndexExists', resolver.operation_name)

    resolver = NewRelic::ElasticsearchOperationResolver.new('DELETE', '/test/things/1')
    assert_equal('DocumentDelete', resolver.operation_name)
  end

  def test_ambiguous_cat_resolver
    resolver = NewRelic::ElasticsearchOperationResolver.new('GET', '_cat/aliases')
    assert_equal('CatAliases', resolver.operation_name)
    assert_equal(nil, resolver.index)
  end

  def test_ambiguousnodes_resolver
    resolver = NewRelic::ElasticsearchOperationResolver.new('GET', '_nodes/12/stats/indices')
    assert_equal('NodeStatsIndices', resolver.operation_name)
  end

  def test_ambiguous_search_resolver
    resolver = NewRelic::ElasticsearchOperationResolver.new('POST', 'test/_search')
    assert_equal('Search', resolver.operation_name)
    assert_equal('Test', resolver.index)
  end

  def test_ambiguous_cluster_resolver
    resolver = NewRelic::ElasticsearchOperationResolver.new('GET', '/_cluster/pending_tasks')
    assert_equal('ClusterPendingTasks', resolver.operation_name)
  end
end
