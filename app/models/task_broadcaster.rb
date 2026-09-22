# In-memory SSE subscriber registry keyed by household id. Single-server only;
# swap for Redis pub/sub if the app ever runs multiple instances.
module TaskBroadcaster
  extend self

  Listener = Struct.new(:queue)

  def broadcast(household_id, payload)
    return unless registry.key?(household_id)

    registry[household_id].each do |listener|
      listener.queue << payload.to_json
    end
  end

  def subscribe(household_id)
    queue = Queue.new
    registry[household_id] << Listener.new(queue)
    queue
  end

  def unsubscribe(household_id, queue)
    return unless registry.key?(household_id)

    registry[household_id].reject! { |listener| listener.queue.equal?(queue) }
    registry.delete(household_id) if registry[household_id].empty?
  end

  def listener_count(household_id)
    registry[household_id]&.size || 0
  end

  private

  def registry
    @registry ||= Hash.new { |hash, key| hash[key] = [] }
  end
end