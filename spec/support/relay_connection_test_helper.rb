module RelayConnectionTestHelper
  def relay_connection_test_query
    <<~GRAPHQL
      query($first: Int, $after: String, $last: Int, $before: String) {
        rebels {
          ships(first: $first, after: $after, last: $last, before: $before) {
            pageInfo {
              hasNextPage
              hasPreviousPage
            }

            edges {
              cursor
              node {
                __typename
                name
              }
            }
          }
        }
      }
    GRAPHQL
  end

  def relay_connection_test_enumerable
    StarWars::DATA["Ship"].values.select { |ship| StarWars::DATA["Faction"]["1"].ships.include?(ship[:id]) }
  end

  def relay_connection_test_execute_query(query, variables)
    star_wars_query(query, variables).to_h
  end

  def test_with_first_and_no_cursor
    results = relay_connection_test_execute_query(relay_connection_test_query, { "first" => 2 })
    assert_nil results["errors"]

    expected_names = relay_connection_test_enumerable.slice(0, 2).map(&:name)

    connection_data = results["data"]["rebels"]["ships"]
    returned_names = connection_data["edges"].map { |edge| edge["node"] }.map { |node| node["name"] }
    assert_equal expected_names, returned_names

    assert_equal false, connection_data["pageInfo"]["hasPreviousPage"]
    assert_equal true, connection_data["pageInfo"]["hasNextPage"]
  end

  def test_with_last_and_no_cursor
    results = relay_connection_test_execute_query(relay_connection_test_query, { "last" => 2 })
    assert_nil results["errors"]

    expected_names = relay_connection_test_enumerable.slice(-2, 2).map(&:name)

    connection_data = results["data"]["rebels"]["ships"]
    returned_names = connection_data["edges"].map { |edge| edge["node"] }.map { |node| node["name"] }
    assert_equal expected_names, returned_names

    assert_equal true, connection_data["pageInfo"]["hasPreviousPage"]
    assert_equal false, connection_data["pageInfo"]["hasNextPage"]
  end

  def test_with_first_and_cursor_of_first_element
    results = relay_connection_test_execute_query(relay_connection_test_query, { "first" => 1 })
    assert_nil results["errors"]
    cursor = results["data"]["rebels"]["ships"]["edges"].first["cursor"]

    results = relay_connection_test_execute_query(relay_connection_test_query, { "first" => 2, "after" => cursor })
    assert_nil results["errors"]

    expected_names = relay_connection_test_enumerable.slice(1, 2).map(&:name)

    connection_data = results["data"]["rebels"]["ships"]
    returned_names = connection_data["edges"].map { |edge| edge["node"] }.map { |node| node["name"] }
    assert_equal expected_names, returned_names

    assert_equal true, connection_data["pageInfo"]["hasPreviousPage"]
    assert_equal true, connection_data["pageInfo"]["hasNextPage"]
  end

  def test_with_first_and_cursor_at_middle_of_collection
    results = relay_connection_test_execute_query(relay_connection_test_query, { "first" => 2 })
    assert_nil results["errors"]

    connection_data = results["data"]["rebels"]["ships"]
    assert_equal 2, connection_data["edges"].length
    cursor = connection_data["edges"].last["cursor"]

    results = relay_connection_test_execute_query(relay_connection_test_query, { "first" => 2, "after" => cursor })
    assert_nil results["errors"]

    expected_names = relay_connection_test_enumerable.slice(2, 2).map(&:name)

    connection_data = results["data"]["rebels"]["ships"]
    returned_names = connection_data["edges"].map { |edge| edge["node"] }.map { |node| node["name"] }
    assert_equal expected_names, returned_names

    assert_equal true, connection_data["pageInfo"]["hasPreviousPage"]
    assert_equal true, connection_data["pageInfo"]["hasNextPage"]
  end

  def test_with_first_and_cursor_at_end_of_collection
    results = relay_connection_test_execute_query(relay_connection_test_query, { "last" => 1 })
    assert_nil results["errors"]

    connection_data = results["data"]["rebels"]["ships"]
    assert_equal 1, connection_data["edges"].length
    cursor = connection_data["edges"].first["cursor"]

    results = relay_connection_test_execute_query(relay_connection_test_query, { "first" => 1, "after" => cursor })
    assert_nil results["errors"]

    connection_data = results["data"]["rebels"]["ships"]
    assert_empty connection_data["edges"]

    assert_equal true, connection_data["pageInfo"]["hasPreviousPage"]
    assert_equal false, connection_data["pageInfo"]["hasNextPage"]
  end

  def test_with_last_and_cursor_of_first_element
    results = relay_connection_test_execute_query(relay_connection_test_query, { "first" => 1 })
    cursor = results["data"]["rebels"]["ships"]["edges"].first["cursor"]

    results = relay_connection_test_execute_query(relay_connection_test_query, { "last" => 2, "before" => cursor })
    assert_nil results["errors"]

    connection_data = results["data"]["rebels"]["ships"]
    assert_equal [], connection_data["edges"]

    assert_equal false, connection_data["pageInfo"]["hasPreviousPage"]
    assert_equal true, connection_data["pageInfo"]["hasNextPage"]
  end

  def test_with_last_and_cursor_at_middle_of_collection
  end

  def test_with_last_and_cursor_at_end_of_collection
  end

  def test_without_first_last_after_before
  end

  def test_with_invalid_cursor
  end

  def test_with_negative_first
  end

  def test_with_negative_after
  end
end
