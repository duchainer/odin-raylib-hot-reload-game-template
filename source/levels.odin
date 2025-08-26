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


// @(rodata)
LEVELS : []Level = {
    // tutorial 0
    {
        lasers = {
            Laser{
                start_p1 = {50, 0},
                start_p2 = {50, 600},
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
            2 * 60,
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
                start_p1 = {50, 0},
                start_p2 = {50, 600},
                lifetime = {
                    current = 0,
                    end = 5 * 60, // seconds * frames
                    repeating = true,
                },
                velocity = {50, 0},
                color = rl.RED,
            },
            Laser{
                start_p1 = {800, 0},
                start_p2 = {800, 600},
                lifetime = {
                    current = 0,
                    end = 12 * 60, // seconds * frames
                    repeating = true,
                },
                velocity = {-50, 0},
                color = rl.RED,
            },
        },
        dialog = {
            {
                0 *60,
                "Next level :D",
            },
        },


        goal = {
            1 * 60,
            Circle{
                center = { WINDOW_WIDTH - 10, WINDOW_HEIGHT/2 + 10/2},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 2
    {
        lasers = {
            Laser{
                start_p1 = {-600, 0},
                start_p2 = {600, 600},
                lifetime = {
                    current = 0,
                    end = 12 * 60, // seconds * frames
                    repeating = true,
                },
                velocity = {50, -50},
                color = rl.RED,
            },
        },
        dialog = {
            {
                0 *60,
                "Top Left?",
            },
        },


        goal = {
            1 * 60,
            Circle{
                center = { 10, 10 },
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 3
    {
        lasers = {
            Laser{
                start_p1 = {50, 0},
                start_p2 = {50, 600},
                lifetime = {
                    current = 0,
                    end = 5 * 60, // seconds * frames
                    repeating = true,
                },
                velocity = {50, 0},
                color = rl.RED,
            },
            Laser{
                start_p1 = {800, 0},
                start_p2 = {800, 600},
                lifetime = {
                    current = 0,
                    end = 12 * 60, // seconds * frames
                    repeating = true,
                },
                velocity = {-50, 0},
                color = rl.RED,
            },
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
        dialog = {
            {
                0 *60,
                "A bit harder, watch out for the laser respawns",
            },
        },


        goal = {
            1 * 60,
            Circle{
                center = { WINDOW_WIDTH - 10, WINDOW_HEIGHT/2 + 10/2},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 4 - Vertical crossing pattern
    {
        lasers = {
            Laser{
                start_p1 = {0, 150},
                start_p2 = {WINDOW_WIDTH, 150},
                lifetime = {
                    current = 0,
                    end = 8 * 60,
                    repeating = true,
                },
                velocity = {0, 30},
                color = rl.RED,
            },
            Laser{
                start_p1 = {0, 450},
                start_p2 = {WINDOW_WIDTH, 450},
                lifetime = {
                    current = 0,
                    end = 8 * 60,
                    repeating = true,
                },
                velocity = {0, -30},
                color = rl.RED,
            },
        },
        dialog = {
            {
                0 * 60,
                "Watch the vertical movement!",
            },
        },
        goal = {
            2 * 60,
            Circle{
                center = {WINDOW_WIDTH/2, WINDOW_HEIGHT/2},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 5 - Fast diagonal sweep
    {
        lasers = {
            Laser{
                start_p1 = {-200, -200},
                start_p2 = {200, 800},
                lifetime = {
                    current = 0,
                    end = 6 * 60,
                    repeating = true,
                },
                velocity = {80, 0},
                color = rl.RED,
            },
            Laser{
                start_p1 = {WINDOW_WIDTH + 200, -200},
                start_p2 = {WINDOW_WIDTH - 200, 800},
                lifetime = {
                    current = 3 * 60,
                    end = 6 * 60,
                    repeating = true,
                },
                velocity = {-80, 0},
                color = rl.BLUE,
            },
        },
        dialog = {
            {
                0 * 60,
                "Blue laser? Still as deadly",
            },
        },
        goal = {
            1 * 60,
            Circle{
                center = {WINDOW_WIDTH/2 + 100, 100},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 6 - Rotating pattern
    {
        lasers = {
            Laser{
                start_p1 = {WINDOW_WIDTH/2, 0},
                start_p2 = {WINDOW_WIDTH/2, WINDOW_HEIGHT},
                lifetime = {
                    current = 0,
                    end = 10 * 60,
                    repeating = true,
                },
                velocity = {40, 40},
                color = rl.RED,
            },
            Laser{
                start_p1 = {0, WINDOW_HEIGHT/2},
                start_p2 = {WINDOW_WIDTH, WINDOW_HEIGHT/2},
                lifetime = {
                    current = 0,
                    end = 10 * 60,
                    repeating = true,
                },
                velocity = {40, -40},
                color = rl.RED,
            },
        },
        dialog = {
            {
                0 * 60,
                "Find the safe spot in the chaos",
            },
        },
        goal = {
            2 * 60,
            Circle{
                center = {80, 80},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 7 - Multiple horizontal waves
    {
        lasers = {
            Laser{
                start_p1 = {0, 100},
                start_p2 = {WINDOW_WIDTH, 100},
                lifetime = {
                    current = 0,
                    end = 6 * 60,
                    repeating = true,
                },
                velocity = {0, 60},
                color = rl.RED,
            },
            Laser{
                start_p1 = {0, 200},
                start_p2 = {WINDOW_WIDTH, 200},
                lifetime = {
                    current = 1 * 60,
                    end = 6 * 60,
                    repeating = true,
                },
                velocity = {0, 60},
                color = rl.ORANGE,
            },
            Laser{
                start_p1 = {0, 300},
                start_p2 = {WINDOW_WIDTH, 300},
                lifetime = {
                    current = 2 * 60,
                    end = 6 * 60,
                    repeating = true,
                },
                velocity = {0, 60},
                color = rl.YELLOW,
            },
        },
        dialog = {
            {
                0 * 60,
                "Wave after wave... stay low!",
            },
        },
        goal = {
            3 * 60,
            Circle{
                center = {WINDOW_WIDTH - 150, WINDOW_HEIGHT - 50},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 8 - Converging beams
    {
        lasers = {
            Laser{
                start_p1 = {0, 0},
                start_p2 = {WINDOW_WIDTH, WINDOW_HEIGHT},
                lifetime = {
                    current = 0,
                    end = 8 * 60,
                    repeating = true,
                },
                velocity = {30, 30},
                color = rl.RED,
            },
            Laser{
                start_p1 = {WINDOW_WIDTH, 0},
                start_p2 = {0, WINDOW_HEIGHT},
                lifetime = {
                    current = 0,
                    end = 8 * 60,
                    repeating = true,
                },
                velocity = {-30, 30},
                color = rl.RED,
            },
            Laser{
                start_p1 = {WINDOW_WIDTH/2, 0},
                start_p2 = {WINDOW_WIDTH/2, WINDOW_HEIGHT},
                lifetime = {
                    current = 4 * 60,
                    end = 4 * 60,
                    repeating = true,
                },
                velocity = {0, 50},
                color = rl.BLUE,
            },
        },
        dialog = {
            {
                0 * 60,
                "X marks the spot... or does it?",
            },
        },
        goal = {
            1 * 60,
            Circle{
                center = {WINDOW_WIDTH/4, WINDOW_HEIGHT/4},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 9 - Spiral pattern
    {
        lasers = {
            Laser{
                start_p1 = {WINDOW_WIDTH/2 - 100, WINDOW_HEIGHT/2},
                start_p2 = {WINDOW_WIDTH/2 + 100, WINDOW_HEIGHT/2},
                lifetime = {
                    current = 0,
                    end = 12 * 60,
                    repeating = true,
                },
                velocity = {20, 20},
                color = rl.RED,
            },
            Laser{
                start_p1 = {WINDOW_WIDTH/2, WINDOW_HEIGHT/2 - 100},
                start_p2 = {WINDOW_WIDTH/2, WINDOW_HEIGHT/2 + 100},
                lifetime = {
                    current = 3 * 60,
                    end = 12 * 60,
                    repeating = true,
                },
                velocity = {20, -20},
                color = rl.BLUE,
            },
            Laser{
                start_p1 = {WINDOW_WIDTH/2 - 70, WINDOW_HEIGHT/2 - 70},
                start_p2 = {WINDOW_WIDTH/2 + 70, WINDOW_HEIGHT/2 + 70},
                lifetime = {
                    current = 6 * 60,
                    end = 12 * 60,
                    repeating = true,
                },
                velocity = {-20, 20},
                color = rl.GREEN,
            },
        },
        dialog = {
            {
                0 * 60,
                "Here is more of a freebie, to breath a bit",
            },
        },
        goal = {
            2 * 60,
            Circle{
                center = {50, 50},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 10 - Alternating vertical sweeps
    {
        lasers = {
            Laser{
                start_p1 = {100, 0},
                start_p2 = {100, WINDOW_HEIGHT},
                lifetime = {
                    current = 0,
                    end = 3.5 * 60,
                    repeating = true,
                },
                velocity = {100, 0},
                color = rl.RED,
            },
            Laser{
                start_p1 = {WINDOW_WIDTH - 100, 0},
                start_p2 = {WINDOW_WIDTH - 100, WINDOW_HEIGHT},
                lifetime = {
                    current = 1.5 * 60,
                    end = 3.5 * 60,
                    repeating = true,
                },
                velocity = {-100, 0},
                color = rl.RED,
            },
            Laser{
                start_p1 = {300, 0},
                start_p2 = {300, WINDOW_HEIGHT},
                lifetime = {
                    current = 3 * 60,
                    end = 3.5 * 60,
                    repeating = true,
                },
                velocity = {100, 0},
                color = rl.ORANGE,
            },
        },
        dialog = {
            {
                0 * 60,
                "Spawns left, goes right, respawn left again...",
            },
        },
        goal = {
            2 * 60,
            Circle{
                center = {WINDOW_WIDTH/2, WINDOW_HEIGHT - 30},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 11 - Box pattern
    {
        lasers = {
            Laser{
                start_p1 = {200, 200},
                start_p2 = {WINDOW_WIDTH - 200, 200},
                lifetime = {
                    current = 0,
                    end = 10 * 60,
                    repeating = true,
                },
                velocity = {0, 30},
                color = rl.RED,
            },
            Laser{
                start_p1 = {200, WINDOW_HEIGHT - 200},
                start_p2 = {WINDOW_WIDTH - 200, WINDOW_HEIGHT - 200},
                lifetime = {
                    current = 0,
                    end = 10 * 60,
                    repeating = true,
                },
                velocity = {0, -30},
                color = rl.RED,
            },
            Laser{
                start_p1 = {200, 200},
                start_p2 = {200, WINDOW_HEIGHT - 200},
                lifetime = {
                    current = 5 * 60,
                    end = 10 * 60,
                    repeating = true,
                },
                velocity = {30, 0},
                color = rl.BLUE,
            },
            Laser{
                start_p1 = {WINDOW_WIDTH - 200, 200},
                start_p2 = {WINDOW_WIDTH - 200, WINDOW_HEIGHT - 200},
                lifetime = {
                    current = 5 * 60,
                    end = 10 * 60,
                    repeating = true,
                },
                velocity = {-30, 0},
                color = rl.BLUE,
            },
        },
        dialog = {
            {
                0 * 60,
                "Goal trapped in a shrinking-ish box?",
            },
        },
        goal = {
            3 * 60,
            Circle{
                center = {WINDOW_WIDTH/2, WINDOW_HEIGHT/2},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 12 - Fast zigzag
    {
        lasers = {
            Laser{
                start_p1 = {0, 100},
                start_p2 = {WINDOW_WIDTH/2, WINDOW_HEIGHT - 100},
                lifetime = {
                    current = 0,
                    end = 4 * 60,
                    repeating = true,
                },
                velocity = {100, 0},
                color = rl.RED,
            },
            Laser{
                start_p1 = {WINDOW_WIDTH/2, 100},
                start_p2 = {WINDOW_WIDTH, WINDOW_HEIGHT - 100},
                lifetime = {
                    current = 2 * 60,
                    end = 4 * 60,
                    repeating = true,
                },
                velocity = {100, 0},
                color = rl.RED,
            },
            Laser{
                start_p1 = {WINDOW_WIDTH, WINDOW_HEIGHT - 100},
                start_p2 = {WINDOW_WIDTH/2, 100},
                lifetime = {
                    current = 1 * 60,
                    end = 4 * 60,
                    repeating = true,
                },
                velocity = {-100, 0},
                color = rl.ORANGE,
            },
        },
        dialog = {
            {
                0 * 60,
                "Quick! Get to safety!",
            },
        },
        goal = {
            1 * 60,
            Circle{
                center = {WINDOW_WIDTH - 150, 50},
                radius = 10,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },

    // level 13 - Final boss pattern - combines multiple previous patterns
    {
        lasers = {
            // Rotating cross
            Laser{
                start_p1 = {WINDOW_WIDTH/2, 0},
                start_p2 = {WINDOW_WIDTH/2, WINDOW_HEIGHT},
                lifetime = {
                    current = 0,
                    end = 15 * 60,
                    repeating = true,
                },
                velocity = {25, 25},
                color = rl.RED,
            },
            Laser{
                start_p1 = {0, WINDOW_HEIGHT/2},
                start_p2 = {WINDOW_WIDTH, WINDOW_HEIGHT/2},
                lifetime = {
                    current = 0,
                    end = 15 * 60,
                    repeating = true,
                },
                velocity = {25, -25},
                color = rl.RED,
            },
            // Sweeping verticals
            Laser{
                start_p1 = {0, 0},
                start_p2 = {0, WINDOW_HEIGHT},
                lifetime = {
                    current = 5 * 60,
                    end = 8 * 60,
                    repeating = true,
                },
                velocity = {80, 0},
                color = rl.BLUE,
            },
            Laser{
                start_p1 = {WINDOW_WIDTH, 0},
                start_p2 = {WINDOW_WIDTH, WINDOW_HEIGHT},
                lifetime = {
                    current = 8 * 60,
                    end = 8 * 60,
                    repeating = true,
                },
                velocity = {-80, 0},
                color = rl.BLUE,
            },
            // Corner diagonal
            Laser{
                start_p1 = {-100, -100},
                start_p2 = {100, WINDOW_HEIGHT + 100},
                lifetime = {
                    current = 10 * 60,
                    end = 6 * 60,
                    repeating = true,
                },
                velocity = {60, 0},
                color = rl.YELLOW,
            },
        },
        dialog = {
            {
                0 * 60,
                "This is it - the final challenge!",
            },
            {
                8 * 60,
                "Stay calm and find your path",
            },
        },
        goal = {
            2 * 60,
            Circle{
                center = {WINDOW_WIDTH - 50, WINDOW_HEIGHT - 50},
                radius = 15,
                color = rl.GREEN,
            },
        },
        additional_level_patterns = {},
    },
}
