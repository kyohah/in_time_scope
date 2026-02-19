# frozen_string_literal: true

module QueryCounter
  def count_queries(&block)
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      count += 1 unless payload[:name] == "SCHEMA"
    }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end

RSpec.configure do |config|
  config.include QueryCounter
end
