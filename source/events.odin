// #+feature dynamic-literals
package game

Needs :: struct {
	food: i32,
	water: i32,
	medecine: i32,
	morale: i32,
	// fuel maybe? for warmth?
	// TODO next iteration, maybe?
}
NeedsLimits :: struct{
	// "X is becoming hungry, and might start doing worse/different decisions"
	soft : Needs,
	// "X is really hungry, and wants to take over the train"
	hard : Needs,
	// "X died from lack of Y. Train morale dropped significantly"
	death : Needs,
}

People :: struct {
	name: [128]u8,
	needs: struct {
		// Every normal day, consumes these from its current.
		daily: Needs,
		// The accumulated needs met at this point, will go down daily until reaching some limits
		current: Needs,
		limits: NeedsLimits,
	},
}


Event :: struct {
	summary_text : string,
	description : string,
	resources_template : string,
	left_choice : string,
	left_choice_modifier: i32,
	right_choice : string,
	people: []People,
	food: i32,
	water: i32,
	medecine: i32,
	fuel: i32,
	morale: i32,
}


BASE_LINE_CURRENT_NEED :: Needs{
	food = 100,
	water = 100,
	medecine = 100,
	morale = 100,
}

BASE_LINE_SOFT_LIMIT :: Needs{
	food = 30,
	water = 30,
	medecine = 30,
	morale = 30,
}

BASE_LINE_HARD_LIMIT :: Needs{
	food = 15,
	water = 15,
	medecine = 15,
	morale = 15,
}

BASE_LINE_DEATH_LIMIT :: Needs{
	food = 0,
	water = 0,
	medecine = 0,
	morale = 0,
}

@(rodata)
events :[1]Event = [1]Event{
    Event {
		summary_text = "some_run_down_workshop",
		description =  "You find an old guy that worked there for 40 years.",
		resources_template =  "And also %v food, %v water and %v medecine.",
		left_choice = "You leave him there, and manage to steal a few resources for the road",
		// A fourth of his resources
		left_choice_modifier = 4,
		right_choice = "You take him with you, he is really interested in how your train is still running.",
		people = {
			People{
				name = {},
				needs = {
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
    },
}
