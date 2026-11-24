class Current < ActiveSupport::CurrentAttributes
  # pending_cards: person-card re-renders waiting to go out (Household.batching_cards).
  attribute :household, :user, :settings, :pending_cards
end
