module InventoryAggregate
  class << self
    # @param event_types [Array<Class<Event>>]
    def on(*event_types, &block)
      @handlers ||= {}
      event_types.each do |event_type|
        @handlers[event_type] = block
      end
    end

    # @param organization_id
    # @return [EventTypes::Inventory]
    def inventory_for(organization_id)
      events = Event.for_organization(organization_id)
      inventory = EventTypes::Inventory.from(organization_id)
      events.group_by { |e| [e.eventable_type, e.eventable_id] }.each do |_, event_batch|
        last_event = event_batch.max_by(&:event_time)
        handle(last_event, inventory)
      end
      inventory
    end

    # @param event [Event]
    # @param inventory [Inventory]
    def handle(event, inventory)
      handler = @handlers[event.class]
      if handler.nil?
        Rails.logger.warn("No handler found for #{event.class}, skipping")
        return
      end
      handler.call(event, inventory)
    end

    # @param payload [EventTypes::InventoryPayload]
    # @param inventory [EventTypes::Inventory]
    # @param validate [Boolean]
    def handle_inventory_event(payload, inventory, validate: true)
      payload.items.each do |line_item|
        inventory.move_item(item_id: line_item.item_id,
          quantity: line_item.quantity,
          from_location: line_item.from_storage_location,
          to_location: line_item.to_storage_location,
          validate: validate)
      end
    end
  end

  on DonationEvent, DistributionEvent, AdjustmentEvent, PurchaseEvent,
    TransferEvent, DistributionDestroyEvent, DonationDestroyEvent,
    PurchaseDestroyEvent, TransferDestroyEvent,
    KitAllocateEvent, KitDeallocateEvent do |event, inventory|
    handle_inventory_event(event.data, inventory, validate: false)
  end

  on AuditEvent do |event, inventory|
    inventory.storage_locations[event.data.storage_location_id].reset!
    handle_inventory_event(event.data, inventory, validate: false)
  end

  on SnapshotEvent do |event, inventory|
    inventory.storage_locations.clear
    inventory.storage_locations.merge!(event.data.storage_locations)
  end
end
