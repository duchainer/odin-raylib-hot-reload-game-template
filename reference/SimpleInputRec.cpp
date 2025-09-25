/******************************************************************************/
// SIMPLE INPUT RECORD/PLAYBACK
// (c) 2015 Brian Provinciano
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

#define INPUTREPLAY_CAN_PLAYBACK	1
#define INPUTREPLAY_CAN_RECORD		1

#define INPUTREPLAY_INCLUDED		(INPUTREPLAY_CAN_PLAYBACK || INPUTREPLAY_CAN_RECORD)
/******************************************************************************/

#if INPUTREPLAY_INCLUDED

#define INPUT_BUTTONS_TOTAL	32		// up to 32
#define MAX_REC_LEN			0x8000	// the buffer size for storing RLE compressed button input (x each button)

/******************************************************************************/
typedef struct
{
	unsigned short *rledata;
	unsigned short rlepos;
	unsigned short datalen;
	unsigned short currentrun;
} ButtonRec;
/******************************************************************************/

// if INPUTREPLAY_CAN_RECORD, as soon as this class is instanced, it will automatically record when instanced/created.
// statically creating this as a global will blanket the entire play session
//
// if INPUTREPLAY_CAN_PLAYBACK, playback will begin as soon as LoadFile() is used
//
class SimpleInputRec
{
    // Only used in SimpleInputRec::Update()
	unsigned int	m_buttonstate;

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
#if INPUTREPLAY_CAN_RECORD
			WriteToFile();
#endif
			delete[] m_data;
		}
	}

	// run each frame before the game uses the live button input.
	// when recording, it saves the live input
	// during playback, it overwrites the live input
	void Update(bool bForce = false);

	// to start a playback
#if INPUTREPLAY_CAN_PLAYBACK
	bool LoadFile(KSTR szfilename);
#endif

	// to finish recording
#if INPUTREPLAY_CAN_RECORD
	void WriteToFile();
#endif

};

/******************************************************************************/

void SimpleInputRec::Update(bool bForce)
{
#if INPUTREPLAY_CAN_RECORD
	if(m_bRecording)
	{
    // Use the actual live input
		unsigned int newbuttons = nesinput.buttons;

		// allocate and initialize
		if(!m_data)
		{
			m_data = new unsigned char[INPUT_BUTTONS_TOTAL * MAX_REC_LEN * 2];
			unsigned short* dataptr = (unsigned short*)m_data;

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

            // if that button state isn't the same as the previous frame, then append next rledata
            // So if I press the button for 4 frames, the pressed part of it will be save as a 4 instead of 1111
            // Space savings is about sqrt of 2, as if I want to encode 8 frames of single value, I only need the value and the length, more-or-less
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
#endif

#if INPUTREPLAY_CAN_PLAYBACK
	if(!m_bRecording)
	{
		bool bIsRunning = false;
		for(int i=0; i<INPUT_BUTTONS_TOTAL; ++i)
		{
			ButtonRec& btn = m_buttons[i];
			if(btn.rledata)
			{
				bIsRunning = true;
				if(!btn.currentrun && btn.rlepos<btn.datalen)
				{
					unsigned short value = btn.rledata[btn.rlepos++];
					btn.currentrun = value&0x7FFF;
					m_buttonstate &= ~(1<<i);
					m_buttonstate |= ((value>>15)&1)<<i;
					--btn.currentrun;
				}
				else
				{
					if(btn.currentrun)
					{
						--btn.currentrun;
					}
					else if(btn.rlepos==btn.datalen)
					{
						btn.rledata = NULL;
					}
				}
			}
		}

		if(bIsRunning)
		{
			// TODO: this is where you can overwrite the live button state to the prerecorded one
			systeminput.buttons = m_buttonstate;
		}
	}
#endif
}

/******************************************************************************/

#if INPUTREPLAY_CAN_PLAYBACK
bool SimpleInputRec::LoadFile(KSTR szfilename)
{
	for(int i=0; i<INPUT_BUTTONS_TOTAL; ++i)
	{
		ButtonRec& btn = m_buttons[i];

		btn.datalen		= 0;
		btn.rledata		= NULL;
		btn.rlepos		= 0;
		btn.currentrun	= 0;
	}

	delete[] m_data;
	m_bRecording = false;

	if(fcheckexists(szfilename))
	{
		FILE* f = fopen(szfilename, "wb");
		if(f)
		{
			// WARNING: You'll want to do more error checking, but just to keep it simple...

			fseek(f,0,SEEK_END);
			unsigned long filelen = ftell(f);
			fseek(f,0,SEEK_SET);

			m_data = new unsigned char[filelen];
			fread(m_data, 1, filelen, f);
			fclose(f);

			unsigned char* bufptr = m_data;
			int numbuttons = bufptr[0] | (bufptr[1]<<8);
			bufptr += 2;
			if(numbuttons <= INPUT_BUTTONS_TOTAL)
			{
				for(int i=0; i<numbuttons; ++i)
				{
					ButtonRec& btn = m_buttons[i];

					btn.datalen = bufptr[0] | (bufptr[1]<<8);
					bufptr += 2;
				}

				for(int i=0; i<numbuttons; ++i)
				{
					ButtonRec& btn = m_buttons[i];
					if(btn.datalen)
					{
						// WARNING: Endian dependent for simplcicity
						btn.rledata = (unsigned short*)bufptr;
						bufptr += btn.datalen*2;
					}
				}
			}
			return true;
		}
	}
	return false;
}
#endif

/******************************************************************************/

#if INPUTREPLAY_CAN_RECORD
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
#endif

/******************************************************************************/

#endif // INPUTREPLAY_INCLUDED
