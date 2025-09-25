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
ButtonRec :: struct {
    // TODO check if it should be u8 or u16
    rledata:    [^]u16,
    rlepos:     u16,
    datalen:    u16,
    currentrun: u16,
}
/******************************************************************************/

// if INPUTREPLAY_CAN_RECORD, as soon as this class is instanced, it will automatically record when instanced/created.
// statically creating this as a global will blanket the entire play session
//
// if INPUTREPLAY_CAN_PLAYBACK, playback will begin as soon as LoadFile() is used
//
SimpleInputRec :: struct {
    // Only used in SimpleInputRec::Update()
    m_buttonstate: u32,

    m_buttons:    [INPUT_BUTTONS_TOTAL]ButtonRec,
    m_bRecording: bool,

    m_data: [^]u8,
}

/******************************************************************************/

SimpleInputRec_Init :: proc(this: ^SimpleInputRec) {
    this.m_buttonstate = 0
    this.m_data = nil
    this.m_bRecording = true
}

SimpleInputRec_Destroy :: proc(this: ^SimpleInputRec) {
    if this.m_data != nil {
        when INPUTREPLAY_CAN_RECORD {
            WriteToFile(this)
        }
        free(this.m_data)
    }
}

// run each frame before the game uses the live button input.
// when recording, it saves the live input
// during playback, it overwrites the live input
Update :: proc(this: ^SimpleInputRec, bForce: bool = false) {
    when INPUTREPLAY_CAN_RECORD {
        if this.m_bRecording {
            // Use the actual live input
            newbuttons := get_input_buttons() // You'll need to implement this

            // allocate and initialize
            if this.m_data == nil {
                this.m_data = cast([^]u8)mem.alloc(INPUT_BUTTONS_TOTAL * MAX_REC_LEN * 2)
                dataptr := cast([^]u16)this.m_data

                for i in 0..<INPUT_BUTTONS_TOTAL {
                    btn := &this.m_buttons[i]

                    btn.rledata = mem.ptr_offset(dataptr, i * MAX_REC_LEN)
                    btn.rlepos = 0
                    btn.currentrun = 0
                    btn.datalen = MAX_REC_LEN
                }
            }

            // write RLE button bit streams
            for i in 0..<INPUT_BUTTONS_TOTAL {
                btn := &this.m_buttons[i]

                // if that button state isn't the same as the previous frame, then append next rledata
                // So if I press the button for 4 frames, the pressed part of it will be save as a 4 instead of 1111
                // Space savings is about sqrt of 2, as if I want to encode 8 frames of single value, I only need the value and the length, more-or-less
                if bForce || (newbuttons & (1 << u32(i))) != (this.m_buttonstate & (1 << u32(i))) || btn.currentrun == 0x7FFF {
                    if btn.currentrun > 0 {
                        bit := (this.m_buttonstate >> u32(i)) & 1
                        btn.rledata[btn.rlepos] = u16((bit << 15) | btn.currentrun)
                        btn.rlepos += 1
                    }
                    btn.currentrun = 1 if !bForce else 0
                } else {
                    btn.currentrun += 1
                }
            }

            this.m_buttonstate = newbuttons
        }
    }

    when INPUTREPLAY_CAN_PLAYBACK {
        if !this.m_bRecording {
            bIsRunning := false
            for i in 0..<INPUT_BUTTONS_TOTAL {
                btn := &this.m_buttons[i]
                if btn.rledata != nil {
                    bIsRunning = true
                    if btn.currentrun == 0 && btn.rlepos < btn.datalen {
                        value := btn.rledata[btn.rlepos]
                        btn.rlepos += 1
                        btn.currentrun = value & 0x7FFF
                        this.m_buttonstate &= ~(1 << u32(i))
                        this.m_buttonstate |= ((value >> 15) & 1) << u32(i)
                        btn.currentrun -= 1
                    } else {
                        if btn.currentrun > 0 {
                            btn.currentrun -= 1
                        } else if btn.rlepos == btn.datalen {
                            btn.rledata = nil
                        }
                    }
                }
            }

            if bIsRunning {
                // TODO: this is where you can overwrite the live button state to the prerecorded one
                systeminput.buttons = this.m_buttonstate
            }
        }
    }
}

/******************************************************************************/

when INPUTREPLAY_CAN_PLAYBACK {
    LoadFile :: proc(this: ^SimpleInputRec, szfilename: string) -> bool {
        for i in 0..<INPUT_BUTTONS_TOTAL {
            btn := &this.m_buttons[i]

            btn.datalen = 0
            btn.rledata = nil
            btn.rlepos = 0
            btn.currentrun = 0
        }

        if this.m_data != nil {
            free(this.m_data)
        }
        this.m_bRecording = false

        if os.exists(szfilename) {
            data, ok := os.read_entire_file(szfilename)
            if ok {
                this.m_data = raw_data(data)

                bufptr := this.m_data
                numbuttons := int(bufptr[0]) | (int(bufptr[1]) << 8)
                bufptr = mem.ptr_offset(bufptr, 2)

                if numbuttons <= INPUT_BUTTONS_TOTAL {
                    for i in 0..<numbuttons {
                        btn := &this.m_buttons[i]

                        btn.datalen = u16(bufptr[0]) | (u16(bufptr[1]) << 8)
                        bufptr = mem.ptr_offset(bufptr, 2)
                    }

                    for i in 0..<numbuttons {
                        btn := &this.m_buttons[i]
                        if btn.datalen > 0 {
                            // WARNING: Endian dependent for simplicity
                            btn.rledata = cast([^]u16)bufptr
                            bufptr = mem.ptr_offset(bufptr, int(btn.datalen) * 2)
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}

/******************************************************************************/

when INPUTREPLAY_CAN_RECORD {
    WriteToFile :: proc(this: ^SimpleInputRec) {
        if this.m_data != nil && this.m_bRecording {
            Update(this, true)

            f, err := os.open("_autorec.rec", os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0o644)
            if err == os.ERROR_NONE {
                defer os.close(f)

                os.write_byte(f, INPUT_BUTTONS_TOTAL)
                os.write_byte(f, 0)

                for i in 0..<INPUT_BUTTONS_TOTAL {
                    btn := &this.m_buttons[i]

                    os.write_byte(f, u8(btn.rlepos))
                    os.write_byte(f, u8(btn.rlepos >> 8))
                }

                for i in 0..<INPUT_BUTTONS_TOTAL {
                    btn := &this.m_buttons[i]

                    // WARNING: Endian dependent for simplicity
                    data_slice := mem.slice_ptr(cast([^]u8)btn.rledata, int(btn.rlepos) * 2)
                    os.write(f, data_slice)
                }
            }
        }
    }
}

/******************************************************************************/

// You'll need to define these input structures somewhere in your code
systeminput: struct {
    buttons: u32,
}

/******************************************************************************/

// Helper function - you'll need to implement this based on your input system
// TODO
get_input_buttons :: proc() -> u32 {
    // Replace this with your actual input reading code
    // For example, if you have an input system that tracks button states:
    // return input_system.current_buttons
    return 0 // placeholder
}

} // when INPUTREPLAY_INCLUDED
