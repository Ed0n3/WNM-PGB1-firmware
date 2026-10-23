with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with MIDI;
with WNM.Fixed_Pools;
with WNM.Project.Arpeggiator;
with WNM.Project.Chord_Sequencer;
with WNM.Project.Step_Sequencer;
with WNM.Project.Storage;
with WNM.File_System;
with WNM.File_System.LEB128_File_Out;
with WNM.Song_Start_Broadcast;
with WNM.Song_Stop_Broadcast;
with WNM.Tasks;
with WNM.Coproc;
with WNM.Mixer;
with WNM.Sample_Library;
with WNM.GUI.Menu;
with WNM.GUI.Menu.Tracks_Mixer;
with WNM.GUI.Menu.Track_Settings.CFW_Tests;
with WNM.Screen;

package body WNM.Project.CFW_Tests is
   use type MIDI.MIDI_Data;
   use type MIDI.MIDI_Channel;
   use type File_System.Storage_Error;
   use type WNM.Chord_Settings.Chord_Notes;
   use type File_System.File_Signed_Size;
   use type Time.Time_Microseconds;
   use type WNM.Coproc.Message_Kind;
   use type WNM_HAL.Mono_Point;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   procedure Drain is
   begin
      WNM.Tasks.Synth_Coproc_Receive;
      WNM.Synth.Process_Coproc_Events;
   end Drain;

   procedure Render_Test_Buffer is
      Reply : WNM.Coproc.Message;
      Success : Boolean;
      Buffer : WNM.Mixer.FX_Send_Buffers renames
        WNM.Mixer.Mixer_Buffers (Mixer_Buffer_Index'First);
   begin
      Buffer.L := (others => (others => 0));
      Buffer.R := (others => (others => 0));
      Synth.Push_Copro_Event
        ((Kind => Coproc.Buffer_Available,
          Buffer_Id => Mixer_Buffer_Index'First));
      Synth.Process_Coproc_Events;
      Coproc.Pop_For_Main (Reply, Success);
      Check (Success and then Reply.Kind = Coproc.Buffer_Available,
             "render returns its audio buffer");
   end Render_Test_Buffer;

   procedure Test_Pool is
      Pool : WNM.Fixed_Pools.Pool (64, 2);
      type Data is array (1 .. 16) of Integer;
      type Ptr is access Data;
      for Ptr'Simple_Storage_Pool use Pool;
      procedure Free is new Ada.Unchecked_Deallocation (Data, Ptr);
      P, Q, R : Ptr;
      Exhausted : Boolean := False;
   begin
      --  Each slot is 32 bytes, so a 64-byte object must be rejected.
      begin
         P := new Data'(others => 1);
      exception
         when Storage_Error => Exhausted := True;
      end;
      Check (Exhausted, "pool must reject oversized allocations");
      --  A second, correctly sized pool checks exhaustion and reuse.
      declare
         P2 : WNM.Fixed_Pools.Pool (128, 2);
         type Access_Data is access Data;
         for Access_Data'Simple_Storage_Pool use P2;
         procedure Release is new Ada.Unchecked_Deallocation
           (Data, Access_Data);
         A, B, C : Access_Data;
      begin
         A := new Data'(others => 41);
         B := new Data'(others => 42);
         Exhausted := False;
         begin
            C := new Data'(others => 43);
         exception
            when Storage_Error => Exhausted := True;
         end;
         Check (Exhausted, "fixed pool capacity");
         Release (A);
         C := new Data'(others => 44);
         Check (B (1) = 42 and then C (16) = 44,
                "pool reuse preserves other slot");
         Release (B);
         Release (C);
      end;
      Free (P);
      Free (Q);
      Free (R);
   end Test_Pool;

   procedure Test_Render is
      Audible : Boolean;
      Buffer : WNM.Mixer.FX_Send_Buffers renames
        WNM.Mixer.Mixer_Buffers (Mixer_Buffer_Index'First);

      procedure Render renames Render_Test_Buffer;
   begin
      Clear;
      Drain;
      --  Exercise allocation and engine reuse across all instrument tracks.
      --  Every instrument family must also render from freshly reused memory.
      for M in Track_Mode_Kind range Sample1_Mode .. Chord_Mode loop
         Clear;
         Drain;
         Audible := False;
         for T in Instrument_Tracks loop
            G_Project.Tracks (T).Mode := M;
            Synchronize_Synth_Settings (T);
            Drain;
            Synth.Push_Copro_Event
              ((Kind => Coproc.MIDI_Event,
                MIDI_Evt => (Kind => MIDI.Note_On,
                             Chan => Voice_MIDI_Chan (T),
                             Key => 60, Velocity => 100)));
            for I in 1 .. 4 loop
               Render;
               Audible := Audible or else
                 (for some Point of Buffer.L (Bypass) => Point /= 0);
            end loop;
         end loop;
         if M not in Sample1_Mode | Sample2_Mode then
            Check (Audible, "instrument produces audio: " & M'Image);
         end if;
      end loop;
      Clear;
      Drain;
   end Test_Render;

   procedure Test_Eight_Samplers is
      use WNM.Sample_Library;
      Sample_Choices : Natural;
      First_Peak : WNM_HAL.Mono_Point;
      Size : File_System.File_Signed_Size;
      Result : File_System.Storage_Error;
   begin
      --  Eight distinct nonempty sample fixtures in the private in-memory ROM.
      for Id in Sample_Index range 0 .. 7 loop
         Sample_Data.all (Id).Audio :=
           (others => WNM_HAL.Mono_Point (1_000 * (Integer (Id) + 1)));
         Sample_Data.all (Id).Len :=
           Sample_Storage_Len (Sample_Point_Count'Last);
      end loop;
      Load;
      Clear;
      Drain;
      for T in Instrument_Tracks loop
         Sample_Choices := 0;
         for I in 1 .. 8 loop
            Next_Value (T, Track_Mode);
            if Mode (T) = Sample_Mode then
               Sample_Choices := Sample_Choices + 1;
            end if;
            Check (G_Project.Tracks (T).Mode /= Sample2_Mode,
                   "duplicate legacy sample mode is hidden");
            Drain;
         end loop;
         Check (Sample_Choices = 1, "exactly one Sample choice per track");
      end loop;
      Clear;
      Drain;
      for I in 0 .. 7 loop
         declare
            T : constant Tracks := Tracks (I + 1);
         begin
            Set (T, Track_Mode, 0.1);
            Check (Mode (T) = Sample_Mode, "sampler on any track");
            Check (G_Project.Tracks (T).CC (A).Value = 0 and then
                   G_Project.Tracks (T).CC (C).Value = 0,
                   "new sampler selects a sample and starts at its beginning");
            for J in 1 .. I loop
               Next_Value (T, CC_Default_A);
            end loop;
            Drain;
         end;
      end loop;
      --  Trigger all eight before rendering, so their envelopes are equal.
      for I in 0 .. 7 loop
         Synth.Push_Copro_Event
           ((Kind => Coproc.MIDI_Event,
             MIDI_Evt =>
               (Kind => MIDI.Note_On,
                Chan => Voice_MIDI_Chan (Tracks (I + 1)),
                Key => MIDI.C4, Velocity => 100)));
      end loop;
      for I in 1 .. 8 loop
         Render_Test_Buffer;
      end loop;
      First_Peak := Synth.L_Peak (Voice_MIDI_Chan (Tracks'First));
      Check (First_Peak > 0, "first sampler produces audio");
      for I in 0 .. 7 loop
         declare
            T : constant Tracks := Tracks (I + 1);
            Peak : constant WNM_HAL.Mono_Point :=
              Synth.L_Peak (Voice_MIDI_Chan (T));
         begin
            Check (Peak > 0, "eight simultaneous sample voices");
            Check (abs (Integer (Peak) -
                        Integer (First_Peak) * (I + 1)) <= 16,
                   "each sampler plays its own distinct sample");
         end;
      end loop;
      Next_Value (Tracks'First, Volume);
      Drain;
      Render_Test_Buffer;
      Check (Synth.L_Peak (Voice_MIDI_Chan (8)) > 0,
             "changing one sampler leaves the eighth playing");
      Result := Storage.Save ("eight-samplers", Size);
      Check (Result = File_System.Ok and then Size > 0,
             "save eight independent samplers");
      Clear;
      Drain;
      Result := Storage.Load ("eight-samplers", Size);
      Check (Result = File_System.Ok, "load eight independent samplers");
      Drain;
      for I in 0 .. 7 loop
         Check (Mode (Tracks (1 + I)) = Sample_Mode and then
                G_Project.Tracks (Tracks (1 + I)).CC (A).Value =
                  MIDI.MIDI_Data (I),
                "independent sample assignments persist");
      end loop;
      Clear;
      Drain;
      Ada.Text_IO.Put_Line
        ("Eight distinct simultaneous samples checked on tracks 1-8");
   end Test_Eight_Samplers;

   procedure Test_Instrument_Modes is
      Expected : constant array (Natural range 0 .. 7) of Track_Mode_Kind :=
        (MIDI_Mode, Sample_Mode, Kick_Mode, Snare_Mode, Hihat_Mode,
         Bass_Mode, Lead_Mode, Chord_Mode);
   begin
      Clear;
      Drain;
      for T in Instrument_Tracks loop
         Set (T, Track_Mode, 0.0);
         Drain;
         for I in Expected'Range loop
            Check (Mode (T) = Expected (I),
                   "instrument selector contains exactly synth/sample/MIDI");
            Editing_Track := T;
            Next_Value_Fast (Track_Mode);
            Check (Mode (T) = Expected ((I + 10) mod Expected'Length),
                   "fast next skips FX modes on instrument tracks");
            Prev_Value_Fast (Track_Mode);
            Check (Mode (T) = Expected (I),
                   "fast previous skips FX modes on instrument tracks");
            Next_Value (T, Track_Mode);
            Drain;
         end loop;
         Check (Mode (T) = MIDI_Mode,
                "instrument mode cycle wraps after chord");
         for I in reverse Expected'Range loop
            Prev_Value (T, Track_Mode);
            Check (Mode (T) = Expected (I), "reverse mode cycle excludes FX");
            Drain;
         end loop;
         for I in 0 .. 100 loop
            Set (T, Track_Mode, WNM_HAL.Touch_Value (Float (I) / 100.0));
            Check (Mode (T) not in Reverb_Mode .. Bitcrush_Mode,
                   "touch strip cannot select FX on tracks 1-8");
            Drain;
         end loop;
      end loop;
      Clear;
      Drain;
      Ada.Text_IO.Put_Line
        ("Synth/sample/MIDI-only selection checked on tracks 1-8");
   end Test_Instrument_Modes;

   procedure Test_Reserved_Tracks is
   begin
      Clear;
      Drain;
      Check (Mode (9) = Reverb_Mode and then Mode (10) = Drive_Mode and then
             Mode (11) = Bitcrush_Mode, "original FX roles are restored");
      Check (G_Project.Tracks (10).CC (A).Value = 127 and then
             G_Project.Tracks (10).CC (D).Value = 31 and then
             G_Project.Tracks (11).CC (A).Value = 70 and then
             G_Project.Tracks (11).CC (B).Value = 30,
             "original drive and bitcrusher defaults are restored");
      for T in Tracks range 9 .. 16 loop
         Check (MIDI_Chan (T) = 0, "reserved tracks keep stock MIDI defaults");
         for Choice in 0 .. 10 loop
            Set (T, Track_Mode, WNM_HAL.Touch_Value (Float (Choice) / 10.0));
            Check (Mode (T) = MIDI_Mode or else Mode (T) = Default_Mode (T),
                   "reserved slider exposes only the original FX/MIDI roles");
            Drain;
         end loop;
         for I in 1 .. 12 loop
            Next_Value (T, Track_Mode);
            Check (Mode (T) = MIDI_Mode or else Mode (T) = Default_Mode (T),
                   "reserved next mode cannot select a synth or sampler");
            Prev_Value (T, Track_Mode);
            Check (Mode (T) = MIDI_Mode or else Mode (T) = Default_Mode (T),
                   "reserved previous mode cannot select a synth or sampler");
            Drain;
         end loop;
      end loop;
      Clear;
      Drain;
      Ada.Text_IO.Put_Line ("Reserved FX/MIDI roles checked on tracks 9-16");
   end Test_Reserved_Tracks;

   procedure Test_Menus is
      use WNM.GUI.Menu;
      Prog : constant Chord_Progressions := Chord_Progressions'First;
      Before : WNM.Chord_Settings.Chord_Notes;
      Volume_8 : WNM_HAL.Audio_Volume;
      subtype Button_Event is Menu_Event_Kind range Up_Press .. B_Press;
      procedure Send (Kind : Button_Event) is
      begin
         WNM.GUI.Menu.On_Event ((Kind => Kind));
         WNM.Screen.Clear;
         WNM.GUI.Menu.Draw;
      end Send;
   begin
      Clear;
      Drain;
      Editing_Song_Elt := Prog;
      Open (Chord_Menu);
      Send (Right_Press); -- The chord's own preset/scale list.
      Before := Selected_Notes (Prog, 1);
      Send (Down_Press); -- First preset -> Custom.
      Check (Selected_Custom (Prog, 1) and then
             Selected_Notes (Prog, 1) = Before,
             "Custom appears in the chord's own preset/scale list");
      Send (A_Press);
      Send (Up_Press);
      Check (Selected_Notes (Prog, 1)(0) = Before (0) + 1,
             "A on the chord's Custom option opens its note editor");
      Send (B_Press);
      Send (Up_Press); -- Custom -> first preset, back on the same selector.
      Check (not Selected_Custom (Prog, 1),
             "B returns to the chord's preset selector");
      WNM.GUI.Menu.On_Event ((Kind => Slider_Touch, Slider_Value => 1.0));
      Check (Selected_Custom (Prog, 1), "touch strip can select Custom");
      Send (Left_Press); -- Back to tonic for the progression navigation test.
      --  Only tonic, preset name and duration precede add/remove.
      for I in 1 .. 3 loop
         Send (Right_Press);
      end loop;
      Send (A_Press);
      Check (Progression_Length (Prog) = 2, "no inline custom-note pages");
      Send (Left_Press); -- The second chord's own preset selector.
      Send (Down_Press);
      Before := Selected_Notes (Prog, 2);
      Send (A_Press);
      Send (Up_Press);
      Check (Selected_Notes (Prog, 2)(0) = Before (0) + 1,
             "A opens the selected chord rather than always the first chord");
      Send (B_Press);
      Send (Right_Press); -- Duration of chord 2.
      Send (Right_Press);
      Send (Right_Press);
      Send (Down_Press); -- Random wraps to Custom in the scale selector.
      Send (A_Press);
      Check (Selected_Custom (Prog, 1) and then Selected_Custom (Prog, 2),
             "Custom scale plus A opens the custom progression editor");
      Before := Selected_Notes (Prog, 1);
      Send (Up_Press);
      Check (Selected_Notes (Prog, 1)(0) = Before (0) + 1,
             "custom editor changes the selected note");
      Send (Right_Press);
      WNM.GUI.Menu.On_Event ((Kind => Slider_Touch, Slider_Value => 0.0));
      Check (Selected_Notes (Prog, 1)(1) = 0, "custom editor supports MIDI 0");
      Send (A_Press);
      Before := Selected_Notes (Prog, 2);
      Send (Down_Press);
      Check (Selected_Notes (Prog, 2)(0) = Before (0) - 1,
             "custom editor advances to the next chord");
      Send (B_Press);
      Before := Selected_Notes (Prog, 2);
      Send (Up_Press); -- Back on the parent scale selector: Custom -> Random.
      Check (Selected_Notes (Prog, 2) = Before, "B returns to scale selector");
      Send (A_Press);
      for Id in Chord_Slot_Id range 1 .. Progression_Length (Prog) loop
         Check (not Selected_Custom (Prog, Id),
                "preset generation replaces custom chords");
      end loop;
      Pop (Success);
      WNM.GUI.Menu.Tracks_Mixer.Push_Window;
      Send (A_Press);
      for I in 1 .. 7 loop
         Send (Right_Press);
      end loop;
      Volume_8 := Track_Volume (8);
      Send (Up_Press);
      Check (Track_Volume (8) = Volume_8 + 1,
             "mixer covers all eight instrument tracks");
      Drain;
      Send (B_Press);
      Clear;
      Drain;
   end Test_Menus;

   procedure Run is
      type MIDI_Key_Array is array (Standard.Positive range <>)
        of MIDI.MIDI_Key;
      T : constant Tracks := 8;
      Prog : constant Chord_Progressions := Chord_Progressions'First;
      Notes : constant WNM.Chord_Settings.Chord_Notes := (0, 61, 73, 127);
      Size : File_System.File_Signed_Size;
      Result : File_System.Storage_Error;
      procedure Put is new File_System.LEB128_File_Out.Push_Gen (Natural);
      Output : File_System.LEB128_File_Out.Instance;
   begin
      Test_Pool;
      Test_Render;
      Test_Eight_Samplers;
      Test_Instrument_Modes;
      Test_Reserved_Tracks;
      WNM.GUI.Menu.Track_Settings.CFW_Tests.Run;
      Test_Menus;
      Clear;
      Drain;
      for Track in Tracks loop
         Check (Mode (Track) = Default_Mode (Track), "track role defaults");
         Check (Voice_MIDI_Chan (Track) = MIDI.MIDI_Channel (Track - 1),
                "internal channel must identify the track");
         --  Instrument tracks are flexible; reserved FX/MIDI roles are fixed.
         for M in Track_Mode_Kind loop
            G_Project.Tracks (Track).Mode := M;
            Check (Mode (Track) = Normalize_Mode (Track, M),
                   "selectable mode");
            Synchronize_Synth_Settings (Track);
            Drain;
         end loop;
      end loop;
      G_Project.Progressions (Prog).Chords (1).Custom := True;
      G_Project.Progressions (Prog).Chords (1).Notes := Notes;
      Check (Selected_Notes (Prog, 1) = Notes, "arbitrary MIDI chord pitches");
      G_Project.Tracks (T).Mode := Lead_Mode;
      G_Project.Tracks (T).Arp_Notes := Custom;
      G_Project.Tracks (T).Arp_Length := 3;
      G_Project.Tracks (T).Arp_Keys :=
        (1 => 61, 2 => 72, 3 => 67, others => 0);
      G_Project.Tracks (T).Arp_Mode := Up;
      Arpeggiator.Signal_Start_Of_Pattern (T);
      for Key of MIDI_Key_Array'(61, 72, 67, 61) loop
         Check (Arpeggiator.Next_Note (T) = Key, "custom arp entry order");
      end loop;
      for Length in Arp_Note_Index loop
         G_Project.Tracks (T).Arp_Length := Length;
         for M in Arp_Mode_Kind loop
            G_Project.Tracks (T).Arp_Mode := M;
            Arpeggiator.Signal_Start_Of_Pattern (T);
            for I in 1 .. 100 loop
               declare
                  Key : constant MIDI.MIDI_Key := Arpeggiator.Next_Note (T);
               begin
                  Check ((for some J in 1 .. Length =>
                            G_Project.Tracks (T).Arp_Keys (J) = Key),
                         "arp stays inside the configured note list");
               end;
            end loop;
         end loop;
      end loop;
      G_Project.Tracks (T).Arp_Notes := Chord;
      G_Project.Tracks (T).Arp_Mode := Up;
      WNM.Song_Start_Broadcast.Broadcast;
      Check (Chord_Sequencer.Current_Chord = Notes,
             "custom progression playback");
      Arpeggiator.Signal_Start_Of_Pattern (T);
      for Key of Notes loop
         Check (Arpeggiator.Next_Note (T) = Key, "arp follows custom chord");
      end loop;

      --  Live recording follows track 8's playhead, not the edit cursor.
      Editing_Track := T;
      Editing_Pattern := 9;
      Editing_Step := 12;
      Step_Sequencer.MIDI_Clock_Tick (0);
      Drain;
      G_Project.Tracks (T).Record_Quantize := True;
      Step_Sequencer.Record_Note (63, 100, Time.Clock + 62_500);
      Check (G_Project.Steps (T)(1)(1).Note = 63 and then
             G_Project.Steps (T)(1)(1).Trig = Always and then
             G_Project.Steps (T)(1)(1).Timing = 0,
             "quantized live recording follows playhead");
      G_Project.Tracks (T).Record_Quantize := False;
      Step_Sequencer.Record_Note (64, 101, Time.Clock + 62_500);
      Check (G_Project.Steps (T)(1)(1).Timing = 64,
             "unquantized onset at half of a 120 BPM step");
      WNM.Song_Stop_Broadcast.Broadcast;
      Drain;
      Result := Storage.Save ("cfw-v2", Size);
      Check (Result = File_System.Ok and then Size > 0, "save v2 project");
      Clear;
      Drain;
      Result := Storage.Load ("cfw-v2", Size);
      Check (Result = File_System.Ok, "load v2 project");
      Check (Selected_Notes (Prog, 1) = Notes, "custom chord round trip");
      Check (G_Project.Tracks (T).Arp_Keys (2) = 72 and then
             not Record_Quantize (T), "arp/record settings round trip");
      Check (G_Project.Steps (T)(1)(1).Timing = 64, "timing round trip");
      Drain;

      --  Stock-format fixture: track 1 is internal kick, track 16 is MIDI.
      Output.Open ("cfw-v1");
      Put (Output, 1);
      for Track in Tracks loop
         Put (Output, 1); Put (Output, Natural (Track));
         Put (Output, 28); Put (Output, 0);
         Put (Output, 255);
      end loop;
      Put (Output, 254);
      File_System.Close;
      Result := Storage.Load ("cfw-v1", Size);
      Check (Result = File_System.Ok and then Mode (1) = Kick_Mode and then
             Mode (8) = Sample_Mode and then Mode (16) = MIDI_Mode,
             "stock project mode migration");
      Drain;
      --  Early custom builds used the old second-sampler ID in v2 projects.
      Output.Open ("legacy-sampler-v2");
      Put (Output, 2);
      for Track in Tracks range 1 .. 3 loop
         Put (Output, 1); Put (Output, Natural (Track));
         Put (Output, 28); Put (Output, Natural (Track) + 8);
         Put (Output, 255);
      end loop;
      Put (Output, 1); Put (Output, 8);
      Put (Output, 28); Put (Output, 2);
      Put (Output, 2); Put (Output, 7);
      Put (Output, 255);
      for Track in Tracks range 9 .. 16 loop
         Put (Output, 1); Put (Output, Natural (Track));
         Put (Output, 28); Put (Output, 2);
         Put (Output, 255);
      end loop;
      Put (Output, 254);
      File_System.Close;
      Result := Storage.Load ("legacy-sampler-v2", Size);
      Check (Result = File_System.Ok and then Size > 0 and then
             G_Project.Tracks (8).Mode = Sample_Mode and then
             G_Project.Tracks (8).CC (A).Value = 7,
             "legacy sample mode loads without resetting its sample");
      for Track in Tracks range 1 .. 3 loop
         Check (G_Project.Tracks (Track).Mode = Lead_Mode,
                "earlier FX assignments on instrument tracks load as Lead");
      end loop;
      for Track in Tracks range 9 .. 16 loop
         Check (G_Project.Tracks (Track).Mode = Default_Mode (Track),
                "earlier custom files cannot reassign reserved FX/MIDI roles");
      end loop;
      Drain;
      Ada.Text_IO.Put_Line
        ("Pool, rendering, routing, chords, arp, recording, storage checked");
   end Run;
end WNM.Project.CFW_Tests;
