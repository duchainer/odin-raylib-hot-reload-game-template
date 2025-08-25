package game
import rl "vendor:raylib"


Level :: struct{
    lasers: []Laser,
    dialog: []struct{
        spawns_at_frame: int,
        text : string,
    },
    goal: struct {
        spawns_at_frame: int,
        using circle : Circle,
    },
    // If we want to reuse a full level pattern of lasers
    // Allow to combine levels in a way
    //
    // Use the Level index
    additional_level_patterns: []int,
}


@(rodata)
LEVELS : []Level = {
    // tutorial 0
    {
        lasers = {
            Laser{
                start_p1 = {0, 0},
                start_p2 = {0, 600},
                lifetime = {
                    current = 0,
                    end = 5 * 60, // seconds * frames
                    repeating = true,
                },
                velocity = {50, 0},
                color = rl.RED,
            },
        },

        dialog = {
            {
                0 *60,
                "Hey, I can time my jump to go above the lasers",
            },
            {
                5 *60,
                "Try to reach the green goals by jumping above the lasers",
            },
            {
                30 *60,
                "",
            },
        },

        goal = {
            5 * 60,
            Circle{
                center = { 12, WINDOW_HEIGHT/2 + 10/2},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 1
    // First real level, try to reach the right side
    {
        lasers = {
            Laser{
                start_p1 = {600, 0},
                start_p2 = {600, 600},
                lifetime = {
                    current = 0,
                    end = 12 * 60, // seconds * frames
                    repeating = true,
                },
                velocity = {-50, 0},
                color = rl.RED,
            },
        },

        goal = {
            5 * 60,
            Circle{
                center = { WINDOW_WIDTH - 10, WINDOW_HEIGHT/2 + 10/2},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },
    //
}
