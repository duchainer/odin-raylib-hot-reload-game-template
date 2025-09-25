package game

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

INPUTREPLAY_CAN_PLAYBACK :: 1
INPUTREPLAY_CAN_RECORD	 :: 1

INPUTREPLAY_INCLUDED	 :: (INPUTREPLAY_CAN_PLAYBACK || INPUTREPLAY_CAN_RECORD)
/******************************************************************************/

when INPUTREPLAY_INCLUDED{

INPUT_BUTTONS_TOTAL :: 32		// up to 32
MAX_REC_LEN		 :: 0x8000	// the buffer size for storing RLE compressed button input (x each button)

/******************************************************************************/
ButtonRec :: struct
{
	u8 *rledata;
	u8 rlepos;
	u8 datalen;
	u8 currentrun;
}
/******************************************************************************/

// if INPUTREPLAY_CAN_RECORD, as soon as this class is instanced, it will automatically record when instanced/created.
// statically creating this as a global will blanket the entire play session
//
// if INPUTREPLAY_CAN_PLAYBACK, playback will begin as soon as LoadFile() is used
//
class SimpleInputRec
{
	uint	m_buttonstate;
	ButtonRec		m_buttons[INPUT_BUTTONS_TOTAL];
	bool			m_bRecording;

	unsigned char*	m_data;

public:
	SimpleInputRec()
	: m_buttonstate(0)
	, m_data(NULL)
	, m_bRecording(true)
	{
	}

	~SimpleInputRec()
	{
		if(m_data)
		{
when INPUTREPLAY_CAN_RECORD{
			WriteToFile();
}
			delete[] m_data;
		}
	}

	// run each frame before the game uses the live button input.
	// when recording, it saves the live input
	// during playback, it overwrites the live input
	void Update(bool bForce = false);

	// to finish recording
when INPUTREPLAY_CAN_RECORD{
	void WriteToFile();
}

};

/******************************************************************************/

void SimpleInputRec::Update(bool bForce)
{
when INPUTREPLAY_CAN_RECORD{
	if(m_bRecording)
	{
		uint newbuttons = nesinput.buttons;

		// allocate and initialize
		if(!m_data)
		{
			m_data = new unsigned char[INPUT_BUTTONS_TOTAL * MAX_REC_LEN * 2];
			u8* dataptr = (u8*)m_data;

			for(int i=0; i<INPUT_BUTTONS_TOTAL; ++i)
			{
				ButtonRec& btn = m_buttons[i];

				btn.rledata = dataptr;
				dataptr += MAX_REC_LEN;

				btn.rlepos = 0;
				btn.currentrun = 0;
				btn.datalen = MAX_REC_LEN;
			}
		}

		// write RLE button bit streams
		for(int i=0; i<INPUT_BUTTONS_TOTAL; ++i)
		{
			ButtonRec& btn = m_buttons[i];

			if(bForce || (newbuttons&(1<<i)) != (m_buttonstate&(1<<i)) || btn.currentrun==0x7FFF)
			{
				if(btn.currentrun)
				{
					int bit = (m_buttonstate>>i)&1;
					btn.rledata[btn.rlepos++] = (bit<<15) | btn.currentrun;
				}
				btn.currentrun = bForce? 0 : 1;
			}
			else
			{
				++btn.currentrun;
			}
		}

		m_buttonstate = newbuttons;
	}
}
}

/******************************************************************************/

/******************************************************************************/

when INPUTREPLAY_CAN_RECORD
void SimpleInputRec::WriteToFile()
{
	if(m_data && m_bRecording)
	{
		Update(true);

		FILE* f = fopen("_autorec.rec","wb");
		if(f)
		{
			fputc(INPUT_BUTTONS_TOTAL, f);
			fputc(0, f);

			for(int i=0; i<INPUT_BUTTONS_TOTAL; ++i)
			{
				ButtonRec& btn = m_buttons[i];

				fputc((unsigned char)btn.rlepos, f);
				fputc(btn.rlepos >> 8, f);
			}
			for(int i=0; i<INPUT_BUTTONS_TOTAL; ++i)
			{
				ButtonRec& btn = m_buttons[i];

				// WARNING: Endian dependent for simplcicity
				fwrite(btn.rledata, 2, btn.rlepos, f);
			}

			fclose(f);
		}
	}
}
}

/******************************************************************************/

} // INPUTREPLAY_INCLUDED
