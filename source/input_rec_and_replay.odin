package game

import "core:os"
import "core:mem"

/******************************************************************************/
// SIMPLE INPUT RECORD/PLAYBACK
// (c) 2015 Brian Provinciano
// (c) 2025 Raphael Duchaine - Converted it to odin-lang
//
// You are free to use this code for your own purposes, no strings attached.
//
// This is a very basic sample to record and playback button input.
// It's most useful when activated on startup, deactivated on shutdown for
// global button recording/playback.
//
// For details on more advanced implementations, see my GDC 2015 session:
// -> Automated Testing and Instant Replays in Retro City Rampage
// The slides and full video will be available on the GDC Vault at a later date.
/******************************************************************************/

/******************************************************************************/
// wrap it so it can be conditionally compiled in.
// for example, set INPUTREPLAY_CAN_RECORD to 1 to play the game and record the input, set it to 0 when done
// INPUTREPLAY_CAN_RECORD takes priority over INPUTREPLAY_CAN_PLAYBACK

INPUTREPLAY_CAN_PLAYBACK :: true
INPUTREPLAY_CAN_RECORD   :: true

INPUTREPLAY_INCLUDED     :: (INPUTREPLAY_CAN_PLAYBACK || INPUTREPLAY_CAN_RECORD)
/******************************************************************************/

when INPUTREPLAY_INCLUDED {

INPUT_BUTTONS_TOTAL :: 32    // up to 32
MAX_REC_LEN         :: 0x8000 // the buffer size for storing RLE compressed button input (x each button)

/******************************************************************************/
Button_Rec :: struct {
    rledata:    [^]u8,
    rlepos:     u16,
    datalen:    u16,
    currentrun: u16,
}
/******************************************************************************/

// if INPUTREPLAY_CAN_RECORD, as soon as this struct is initialized, it will automatically record when created.
// statically creating this as a global will blanket the entire play session
//
// if INPUTREPLAY_CAN_PLAYBACK, playback will begin as soon as load_file() is used
//
Simple_Input_Rec :: struct {
    buttonstate: u32,
    buttons:     [INPUT_BUTTONS_TOTAL]Button_Rec,
    recording:   bool,
    data:        []u8,
}

/******************************************************************************/

simple_input_rec_init :: proc(rec: ^Simple_Input_Rec) {
    rec.buttonstate = 0
    rec.recording = true
    rec.data = nil
}

simple_input_rec_destroy :: proc(rec: ^Simple_Input_Rec) {
    if rec.data != nil {
        when INPUTREPLAY_CAN_RECORD {
            write_to_file(rec)
        }
        delete(rec.data)
    }
}

// run each frame before the game uses the live button input.
// when recording, it saves the live input
// during playback, it overwrites the live input
simple_input_rec_update :: proc(rec: ^Simple_Input_Rec, force: bool = false) {
    when INPUTREPLAY_CAN_RECORD {
        if rec.recording {
            // Replace with your actual input system
            newbuttons: u32 = get_input_buttons() // You'll need to implement this

            // allocate and initialize
            if rec.data == nil {
                rec.data = make([]u8, INPUT_BUTTONS_TOTAL * MAX_REC_LEN * 2)
                dataptr := raw_data(rec.data)

                for i in 0..<INPUT_BUTTONS_TOTAL {
                    btn := &rec.buttons[i]

                    btn.rledata = cast([^]u8)(uintptr(dataptr) + uintptr(i * MAX_REC_LEN))
                    btn.rlepos = 0
                    btn.currentrun = 0
                    btn.datalen = MAX_REC_LEN
                }
            }

            // write RLE button bit streams
            for i in 0..<INPUT_BUTTONS_TOTAL {
                btn := &rec.buttons[i]

                button_changed := (newbuttons & (1 << uint(i))) != (rec.buttonstate & (1 << uint(i)))

                if force || button_changed || btn.currentrun == 0x7FFF {
                    if btn.currentrun > 0 {
                        bit := (rec.buttonstate >> uint(i)) & 1
                        // Store as 16-bit value: bit in high bit, run length in lower 15 bits
                        value := u16((bit << 15) | btn.currentrun)

                        // Write 16-bit value (little endian)
                        btn.rledata[btn.rlepos * 2] = u8(value & 0xFF)
                        btn.rledata[btn.rlepos * 2 + 1] = u8(value >> 8)
                        btn.rlepos += 1
                    }
                    btn.currentrun = 1 if !force else 0
                } else {
                    btn.currentrun += 1
                }
            }

            rec.buttonstate = newbuttons
        }
    }
}

/******************************************************************************/

when INPUTREPLAY_CAN_RECORD {
    write_to_file :: proc(rec: ^Simple_Input_Rec) {
        if rec.data != nil && rec.recording {
            simple_input_rec_update(rec, true)

            file, err := os.open("_autorec.rec", os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0o644)
            if err == os.ERROR_NONE {
                defer os.close(file)

                // Write header
                os.write_byte(file, INPUT_BUTTONS_TOTAL)
                os.write_byte(file, 0)

                // Write button data lengths
                for i in 0..<INPUT_BUTTONS_TOTAL {
                    btn := &rec.buttons[i]
                    os.write_byte(file, u8(btn.rlepos & 0xFF))
                    os.write_byte(file, u8(btn.rlepos >> 8))
                }

                // Write button data
                for i in 0..<INPUT_BUTTONS_TOTAL {
                    btn := &rec.buttons[i]
                    // Write the RLE data (16-bit values)
                    data_slice := ([^]u8)(btn.rledata)[:btn.rlepos * 2]
                    os.write(file, data_slice)
                }
            }
        }
    }
}

/******************************************************************************/

// Helper function - you'll need to implement this based on your input system
get_input_buttons :: proc() -> u32 {
    // Replace this with your actual input reading code
    // For example, if you have an input system that tracks button states:
    // return input_system.current_buttons
    return 0 // placeholder
}

} // when INPUTREPLAY_INCLUDED
