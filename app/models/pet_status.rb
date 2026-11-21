# Where a pet is and how fed it is today, as shown on its card.
PetStatus = Struct.new(:pet, :report, :fed_today, :last_feeding, keyword_init: true) do
  def meals
    pet.meals_per_day
  end

  # Pets nobody here feeds (meals_per_day 0) have no fed status at all.
  def tracks_meals?
    meals.positive?
  end

  # :hungry (nothing yet today), :partly (some meals), :fed (all of them).
  def fed_state
    if fed_today >= meals then :fed
    elsif fed_today.zero? then :hungry
    else :partly
    end
  end
end
