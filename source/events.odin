package game

@(rodata)
events := [?]Event{
    Event {
		summary_text = "some_run_down_workshop",
		description =  "You find an old guy that worked there for 40 years."+"%",
		resources_template =  "And also %v food, %v water and %v medecine.",
		left_choice = "You leave him there, and manage to steal a few resources for the road",
		// A fourth of his resources
		left_choice_modifier = 4,
		right_choice = "You take him with you, he is really interested in how your train is still running.",
		people = []People{
			People{
				name = "Paul",
				needs = struct {
					// Every normal day, consumes these from its current.
					daily = Needs{
						food = 1,
						water = 1,
						// He needs a bit of medecine every day, for his aging ailments
						medecine = 1,
						// He doesn't need much to stay motivated
						morale = 0,
					},
					// The accumulated needs met at this point, will go down daily until reaching some limits
					current = BASE_LINE_CURRENT_NEED,
					limits = NeedsLimits{
						// "X is becoming hungry, and might start doing worse/different decisions"
						soft = BASE_LINE_SOFT_LIMIT,
						// "X is really hungry, and wants to take over the train"
						hard = BASE_LINE_HARD_LIMIT,
						// "X died from lack of Y. Train morale dropped significantly"
						death = BASE_LINE_DEATH_LIMIT,
					},
				},
			},
		},
		food = 10,
		water = 20,
		medecine = 25,
		fuel = 0,
		morale = 5,
    },
}
